clean:	
	find . -iname \*~ -exec rm -rfv {} \;
	find . -iname \*.~\* -exec rm -rfv {} \;
	find . -iname \*.exe -exec rm -rfv {} \;
	find . -iname \*.dcu -exec rm -rfv {} \;

readme:
	perldoc -o Markdown acl.pl > README.md

