#!/usr/bin/perl
# "acl.pl"
# Copyright (c) 2005, 2006 Flavio S. Glock.  All rights reserved.  This
# program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
# TODO
# - rename _val(), _op() -- may clash with compiled programs
# - thread error in Windows XP, PAR error.
# - movement simulator
# - serial port simulator
# - remove // is a comment
# - array boundary check
# - "suspend"
# - fix the parser:  a[1]+x => $a [ 1 ] +x
#
# CHANGES
# 0.10 - --trace option
# 0.11 - separate main and globals processing
# 0.12 - main loop
# 0.13 - "stat"
#      - forbids calling more than an instance (sub+run or run+run) of the same program
# 0.14 - better control of "run" timeout in programs that don't have "main"
# 0.15 - BEGIN block, avoid duplicating code
# 0.16 - "stop" doesn't stop main; "die" moved to main thread
#      - help is automatic; --version option
#      - all messages in english
# 0.17 - "status" is complete; "priority" works
# 0.18 - "wait"; parser fixes
# 0.19 - "dim", "dimg"; parser fixes; adjusted "for", "pend", "post"
# 0.20 - fixed "print" vector var
# 0.21 - fixed the missed new line when using --version argument
# 0.22 - parser fix: + - / operations
# 0.23 - expressions may have parenthesis
# 0.24 - force integer arithmetic
# 0.25 - pod: use with PAR "pp"
# 0.26 - force lowercase
# 0.27 - "use integer" to avoid an error in PerlApp
# 0.28 - println emits \n before printing
# 0.29 - <> difference
# 0.30 - GET VAR

use strict;

# preload modules 
use threads;
use threads::shared;
use Getopt::Long;
use Term::ReadKey;

{
    use integer;  # make PerlApp happy
}

use vars qw( $version );
$version = 0.30;

use vars qw( $header $control_vars $main_loop $lib );

BEGIN {

    $control_vars = <<'EOT';  
$|=1;
use vars qw( %running %stop %start %delay %suspend %priority $die );
share( %running );
share( %stop );
share( %start );
share( %delay );
share( %suspend );
share( %priority );
share( $die );
EOT

    $header = <<'EOT';         
#!/usr/bin/perl
use strict; 
use threads;
use threads::shared;
use Term::ReadKey;
EOT

    $main_loop = <<'EOT';
my $running = 0;
while ( $running < 5 )
{
    if ( $die )
    {
        warn "Runtime error: $die\n";
        last;
    }
    my $run = 0;
    for ( keys %start )
    {
        if ( $start{$_} )
        {
            $die = "program $_ already running" if $start{$_} > 1;
            $start{$_} = 0;
            $die = "program $_ already running" if $running{$_};
            $running{$_} = 1;
            $stop{$_} = 0;
            $priority{$_} = 5 unless defined $priority{$_};
            threads->new( '_' . $_ );
            $running = 0;
        } 
        $run += $running{$_};
    }
    $running ++ if ! $run;
    select( undef, undef, undef, 0.1 );
}
# select( undef, undef, undef, 0.5 );
foreach my $thr (threads->list) {
    # Don't join the main thread or ourselves
    if ($thr->tid && !threads::equal($thr, threads->self)) {
        $thr->join;
    }
}
EOT

    $lib = <<'EOT';

sub __stat {
    print "job name \tpriority \tstatus\n";
    for ( keys %running )
    {
        next if $_ eq '_main';
        next unless $running{$_};
        print sprintf( "%-10s   \t", uc($_) );
        print sprintf( "%05d    \t", $priority{$_} );    # XXX comando "priority"
        if ( $suspend{$_} )
        {
            print "SUSPEND";
        }
        elsif ( $delay{$_} )
        {
            print "DELAY";
        }
        else
        {
            print "PEND";
        }
        print "\n";
    }
}

sub __delay {
    my ( $program, $delay ) = @_;
    $delay{$program} = $delay;
    select( undef, undef, undef, $delay / 100.0 );
    $delay{$program} = 0;
}

EOT

    eval $control_vars;
    eval "sub __main_thread { $main_loop } ";
} # BEGIN


sub _val {  ( $_[0] =~ /^[a-z]/ ) ? "\$@_" : "@_" }
sub _op { local $_ = shift; s/^=$/==/; $_ }
sub __shift_var {
    my @tmp;
    my $token;
    $token = shift @{$_[0]};
    return @tmp unless defined $token;
    push @tmp, $token;
    return @tmp if $token =~ /^"/ || @{$_[0]} == 0 || $_[0][0] ne "[";    #"
    my $paren = 1;
    while( @{$_[0]} )
    { 
        $_ = shift @{$_[0]}; 
        $paren++ if $_ eq '[';
        $paren-- if $_ eq ']';
        push @tmp, $_;
        last if $_ eq ']' && $paren == 0;
    }
    return @tmp;
}
sub __list {
    my $tmp;
    my @list = @_;
    while ( @list )
    {
        $tmp .= ',' if $tmp;
        $tmp .= join( "", map { _val($_) } __shift_var( \@list ) );
    }
    return $tmp;
}

{

my $program;

my %_interpreta = (
    ( map { $_ => sub { } } 
          '' , qw( * delvar mprofile echo noecho quiet noquiet ) ),
    if =>      sub { "if ( ( " . join( ' ', map { _op(_val($_)) } @_ ) . " )" },
    andif =>   sub { "  && ( " . join( ' ', map { _op(_val($_)) } @_ ) . " )" },
    orif =>    sub { "  || ( " . join( ' ', map { _op(_val($_)) } @_ ) . " )" },
    else =>    sub { "} else {" },
    endif =>   sub { "}" },
    program => sub { 
        $program = $_[0]; 
        "sub _@_ { " .
        "use integer;"
    },
    end =>     sub { 
        my $p = $program;
        undef $program; 
        "\$running{$p} = 0; " .
        "}"; 
    },
    gosub =>   sub { 
        "\$die = 'program $_[0] already running' if \$running{$_[0]}; " .
        "\$running{$_[0]} = 1; " .
        "\$stop{$_[0]} = 0; " .
        '$priority{' . $_[0] . '} = 5 unless defined $priority{' . $_[0] . '}; ' .
        "_@_();" 
    },
    run =>     sub { 
        "\$die = 'program $_[0] already running' if \$running{$_[0]}; " .
        '$start{' . $_[0] . '} += 1;'   # XXX ++ doesn't work here
    },
    label =>   sub { "L@_: ;" },
    goto =>    sub { "goto L@_;" },
    print =>   sub { 'print ' . __list( @_ ) . ";" },
    println => sub { 'print "\n" . ' . __list( @_ ) . ";" },
    define =>  sub { 
        "my (" . __list( @_ ) . ");\n" .
        join( "\n", map { _val($_) . " = 0;" } @_ ) 
    },
    dim =>     sub { 
        "my \@$_[0];\n" .
        "\$${_[0]}[\$_] = 0 for 1 .. $_[2];" 
    },
    global =>  sub { 
        "use vars qw(" . join( " ", map { _val($_) } @_ )  . ");\n" .
        join( "\n", map { _val($_) . " = 0;" } @_ ) . "\n" .
        join( "\n", map { "share(" . _val($_) . ");" } @_ )
    },
    dimg =>     sub { 
        "use vars qw( \@$_[0] );\n" .
        "share( \@$_[0] );\n" .
        "\$${_[0]}[\$_] = 0 for 1 .. $_[2];" 
    },
    set =>     sub { join( ' ', map { _val($_) } @_ ) . ";" },
    pend =>    sub {
        my $var1; while(@_){ $_ = shift; last if $_ eq 'from';  $var1 .= _val( $_ ) };
        my $var2; while(@_){ $_ = shift; $var2 .= _val( $_ ) };
        # If var2 has a non-zero value, that value is assigned to var1 
        # and the value of var2 is set to zero.
        '$suspend{' . $program . '} = 1; ' .
        "while( $var2 == 0 ) { select( undef, undef, undef, 0.05 ) }; " .
        '$suspend{' . $program . '} = 0; ' .
        "$var1 = $var2; $var2 = 0;"
    },
    wait =>    sub {
        '$suspend{' . $program . '} = 1; ' .
        "while( !(" . join( ' ', map { _op(_val($_)) } @_ ) . ") ) { select( undef, undef, undef, 0.05 ) }; " .
        '$suspend{' . $program . '} = 0; ' 
    },
    post =>    sub {
        my $var1; while(@_){ $_ = shift; last if $_ eq 'to';  $var1 .= _val( $_ ) };
        my $var2; while(@_){ $_ = shift; $var2 .= _val( $_ ) };
        "$var2 = $var1;"
    },
    delay =>   sub { '__delay( "' . $program . '", ' . _val(@_) . " );" },
    for =>     sub {
        my $nome; while(@_){ $_ = shift; last if $_ eq '=';  $nome .= _val( $_ ) };
        my $ini;  while(@_){ $_ = shift; last if $_ eq 'to'; $ini .=  _val( $_ ) };
        my $end;  while(@_){ $_ = shift; $end .= _val( $_ ) };
        "for ( $nome = $ini; " .
            "( $ini <= $end ? $nome <= $end : $nome >= $end ); " .
            "$nome += ( $ini <= $end ? 1 : -1 ) ) {";
    },
    endfor =>  sub { "}"; },
    read =>    sub { 
        my $tmp;
        my @list = @_;
        while ( @list )
        {
            my $tmp1 = join( "", map { _val($_) } __shift_var( \@list ) );
            if ( $tmp1 =~ /^\$/ )
            {
                $tmp .= "print \" > \"; $tmp1 = <>; chomp $tmp1;" 
            }
            else
            {
                $tmp .= "print $tmp1;"
            }
        }
        return $tmp;
    },
    get =>    sub { 
        my $tmp;
        my @list = @_;
        my $tmp1 = join( "", map { _val($_) } __shift_var( \@list ) );
        if ( $tmp1 =~ /^\$/ )
        {
            $tmp .= "ReadMode(3); $tmp1 = ord(ReadKey(0)); ReadMode(0);" 
        }
        return $tmp;
    },
    stop =>    sub {
        return "\$stop{$_[0]} = 1;" if $_[0];
        '$stop{$_} = 1 for keys %running;'
    },
    stat =>    sub { '__stat();' },
    priority => sub { '$priority{' . $_[0] . '} = ' . _val($_[1]) . ';' }
);

my $debug = 0;
my $preprocess = 0;
my $trace = 0;
my $help = 0;
my %opt = ( 
    "debug" => \$debug, 
    "perl" =>  \$preprocess, 
    "trace" => \$trace,
    "version" => sub { print "acl version $version\n"; exit },
);
my $opt = join( '] [--', 'help', keys %opt );
$opt{help} = sub
{
    print "acl - version $version\n";
    print "\n";
    print "Interpreter/compiler for the ACL (Advanced Control Language) robot control language\n";
    print "\n";
    print "  acl [--$opt] program.acl\n";
    print "\n";
    print "  ACL commands: ";
    print "    " . $_ . "\n" for sort { length $a cmp length $b } keys %_interpreta;
    exit;
};
my $result = GetOptions ( %opt );
my $source_name = shift;

if ( ! $help && ! $source_name )
{
    print "  acl [--$opt] program.acl\n";
    exit;
}

    my $if = 0;
    my $globals;
    my $main;
    my $out;
    $main .= $_interpreta{'program'}('_main') . "\n";
    my $source;
    open ( $source, '<', $source_name ) 
        or die "$!";

while (<$source>)
{
    chomp;
    my $src = $_;

    # perlfaq -  How can I split a [character] delimited string ...
    my @t;
    push(@t, defined($1) ? $1:$3) 
	while m/("[^"\\]*(\\.[^"\\]*)*")|([^\s]+)/g;

    @t = map {
        if ( /^"/ )         #"
        {
            $_;
        }
        else
        {
            $_ = lc;
            $_ =~ s/([\[\]\*\/\+\-\(\)]|[<>=]+)/ $1 /g;
            s{//.*}{};
            s/^\s+|\s+$//g;
            split /\s/, $_;
        }
    } @t;

    my $cmd = shift @t;
    next unless $cmd;
    die "Unknown command: $cmd" unless exists $_interpreta{$cmd};

    if ( $cmd eq 'global' || $cmd eq 'dimg' ) {
        $globals .= $_interpreta{$cmd}(@t) . "\n";
        next;
    }

    my $line;
    my $is_main = $cmd ne 'program' && ! $program;
    if ( $if && $cmd ne 'andif' && $cmd ne 'orif' ) {
        $if = 0;
        $line .= "   ) {\n";
    }
    $if = 1 if $cmd eq 'if';
    $line .= $_interpreta{$cmd}(@t);
    $line .= " if ( \$stop{$program} ) { \$running{$program} = 0; return; }" 
        if ! $is_main && $program && ! $if;
    if ( $trace )
    {
        $src =~ s/"/\\"/g;
        $line .= ' print "  ' . sprintf( "%03d", $. ) . ": " . $src . '\n"; ' 
            if ! $if && $cmd ne 'end' && $cmd ne 'global' && $cmd ne 'else' 
               && $cmd ne 'endif';
    }
    elsif ( $debug )
    {
        $line .= "    \t# " . sprintf( "%03d", $. ) . ": $src";
    }
    $line .= "\n";
    if ( $is_main )
    {
        $main .= $line
    }
    else
    {
        $out .= $line
    }
}
    close ( $source );
    $program = '_main';
    $main .= $_interpreta{'end'}() . "\n";
    $main .= $_interpreta{'run'}('_main') . "\n";

    for ( $globals, $lib, $out, $main ) {
        s/(?<!= )<>/!=/sg;  # "2 <> 2", but not "$k = <>"
    }

    if ( $preprocess )
    {
        print $header, $control_vars, $globals, $lib, $out, $main, $main_loop;
        exit;
    }
    $out = $globals . $lib . $out . $main;
    print STDERR $out if $debug;
    eval $out 
        or die "Compile error: $@";
    __main_thread();

}

__END__

=head1 NAME

acl - interpreter for the ACL (Advanced Control Language) robot control language

=head1 SYNOPSIS

Run a program

  $ ./acl test.acl    

Show program lines while executing

  $ ./acl --trace test.acl

Show the program Perl would execute 

  $ ./acl --perl test.acl

Show help, version

  $ ./acl --help
  $ ./acl --version

=head1 COMPILING INTO EXECUTABLE FILES

The programs can be transformed into executables by using the "pp" utility 
that comes with the Perl PAR module.

To compile par.pl:

  $ pp -o acl.exe acl.pl

To compile an ACL program:

  $ ./acl --perl myprogram.acl > myprogram.pl
  $ pp -o myprogram.exe myprogram.pl

=head1 SEE ALSO

ACL can be found in Google using:

  scorbot define global println delay

PAR and pp

=head1 AUTHOR

Flavio S. Glock <fglock@pucrs.br>

=head1 COPYRIGHT

Copyright (c) 2005 Flavio S. Glock.  All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
