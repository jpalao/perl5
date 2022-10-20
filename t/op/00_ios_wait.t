#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all('iOS only test') if $^O !~ /darwin-ios/;
}

sleep(180) if $^O =~ /darwin-ios/;
ok( 1,         "sleep for 3m on iOS..." );
# try to avoid iOS killing tests for excessive CPU usage
# during t/op tests