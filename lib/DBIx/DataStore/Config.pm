package DBIx::DataStore::Config;

use v5.10;
use strict;
use warnings;

use File::HomeDir;
use File::Spec;
use YAML;

sub new {
    my ($class, %opts) = @_;

    my $self = {};

    $self = bless $self, $class;

    $self->{'_raw_config'} = $opts{'config'} && ref($opts{'config'}) eq 'HASH'
        ? normalize_config($opts{'config'})
        : normalize_config(read_config(find_config_file()));

    $self->pick_datastore($opts{'store'} ? $opts{'store'} : 'default');

    return $self;
}

sub find_config_file {
    my $home = File::HomeDir->my_home();

    my $path;
    my $root = File::Spec->rootdir;

    # Per user configurations first
    return $path if $path = File::Spec->join($home, '.datastore', 'config.yml') && -f $path && -r $path;
    return $path if $path = File::Spec->join($home, '.datastore.yml') && -f $path && -r _;

    # Global configurations last
    return $path if $path = File::Spec->join($root, 'etc', 'datastore', 'config.yml') && -f $path && -r _;
    return $path if $path = File::Spec->join($root, 'etc', 'datastore.yml') && -f $path && -r _;

    return;
}

sub normalize_config {
    my ($orig) = @_;
}

sub pick_datastore {
    my ($self, $name) = @_;
}

sub read_config {
    my ($path) = @_;
}

1;
