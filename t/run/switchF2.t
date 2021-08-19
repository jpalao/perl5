#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl';
    skip_all('iOS: stdin not supported') if $^O =~ /darwin-ios/;
}

plan(tests => 3);

{ # perl #116190
  fresh_perl_is('print qq!@F!', '1 2',
		{
		 stdin => "1:2",
		 switches => [ '-n', '-F:' ],
		}, "passing -F implies -a");
  fresh_perl_is('print qq!@F!', '1 2',
		{
		 stdin => "1:2",
		 switches => [ '-F:' ],
		}, "passing -F implies -an");
  fresh_perl_is('print join q!,!, @F', '1,2',
		{
		 stdin => "1 2",
		 switches => [ '-a' ],
		}, "passing -a implies -n");
}
