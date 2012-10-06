use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'DBIx::DataStore',
    license             => 'perl',
    dist_author         => q{Jon Sime <jonsime@gmail.com>},
    dist_version_from   => 'lib/DBIx/DataStore.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'perl' => '5.10.0',
        'DBI'  => 1.601,
        'YAML' => '0.80',
    },
    add_to_cleanup      => [ 'DBIx-DataStore-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
