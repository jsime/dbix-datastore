#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'DBIx::DataStore' ) || print "Bail out!\n";
}

diag( "Testing DBIx::DataStore $DBIx::DataStore::VERSION, Perl $], $^X" );
