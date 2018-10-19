# NAME

acl - interpreter for the ACL (Advanced Control Language) robot control language

# SYNOPSIS

Run a program

    $ ./acl test.acl    

Show program lines while executing

    $ ./acl --trace test.acl

Show the program Perl would execute 

    $ ./acl --perl test.acl

Show help, version

    $ ./acl --help
    $ ./acl --version

# COMPILING INTO EXECUTABLE FILES

The programs can be transformed into executables by using the "pp" utility 
that comes with the Perl PAR module.

To compile par.pl:

    $ pp -o acl.exe acl.pl

To compile an ACL program:

    $ ./acl --perl myprogram.acl > myprogram.pl
    $ pp -o myprogram.exe myprogram.pl

# SEE ALSO

ACL can be found in Google using:

    scorbot define global println delay

PAR and pp

# AUTHOR

Flavio S. Glock <fglock@pucrs.br>

# COPYRIGHT

Copyright (c) 2005 Flavio S. Glock.  All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
