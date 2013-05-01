package DBIx::DataStore::Config;

use 5.010;
use strict;
use warnings;

use File::HomeDir;
use File::Spec;
use Memoize;
use Storable qw( freeze thaw );
use YAML qw( LoadFile );

=head1 NAME

DBIx::DataStore::Config - Configuration management for DBIx::DataStore

=head1 DESCRIPTION

Please refer to the documentation in DBIx::DataStore for details on using
this package.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Jon Sime, Buddy Burden.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

memoize('truthiness');

=head2 new

Constructor for the internal configuration object. Takes an optional hash
argument with two keys currently supported:

=over 4

=item config

Instead of reading the configuration from a file at one of the pre-defined
locations, the configuration may be passed in as a hash reference. The structure
of this hash reference should mirror that of the parsed version of the YAML
configuration files.

=item store

The name of the datastore to use from the configuration.

=back

=cut

sub new {
    my ($class, %opts) = @_;

    my $self = {};

    $self = bless $self, $class;

    $self->{'config'} = $opts{'config'} && ref($opts{'config'}) eq 'HASH'
        ? normalize_config($opts{'config'})
        : normalize_config(read_config(find_config_file()));

    $self->server($self->pick_datastore($opts{'store'} ? $opts{'store'} : 'default'));

    return $self;
}

=head2 dsn

Returns the DBI compatible DSN connection string for the currently selected
datastore. Nothing will be returned if there is no datastore selected.

=cut

sub dsn {
    my ($self, $reader) = @_;

    my $server = $self->server;
    return unless $server;

    my $driver = $self->option('driver', undef, $reader);

    my @parts;
    push(@parts, sprintf('%s=%s', $_, $self->option($_, undef, $reader))) for qw( database host port );

    return sprintf('dbi:%s:%s', $driver, join(';', @parts));
}

=head2 options

Returns a list of configuration options from currently selected datastore.

=cut

sub options {
    my ($self) = @_;

    # TODO return list of configuration options set for selected datastore (does not include names of servers or DSN information)
}

=head2 option

Provides access to retrieve or modify the various settings for the currently
selected datastore. Accepts one to three arguments.

The first argument should be the name of the setting. If this is the only
argument provided, the currently configured value of that setting for the
datastore's primary server, if it exists, will be returned and no other
action will be taken.

The second argument, if passed, will modify the setting to that value (pending
any validation that may be necessary for different settings). The value will
then be returned after it has been modified.

A third argument may also be passed, which if given should be the name of
one of the datastore's read-only servers. This will cause the setting in
question to be set/get'ed from the reader's configuration instead of the
primary's. In cases where you wish to only retrieve the value, and not
modify it, the second argument may be passed as C<undef> which will
prevent any changes from being made to the configuration.

=cut

sub option {
    my ($self, $name, $value, $reader) = @_;

    my $server = $self->server;

    if (defined $reader) {
        return unless exists $self->{'config'}{$server}{'readers'}{$reader};

        $self->{'config'}{$server}{'readers'}{$reader}{$name} = $value if defined $value;
        return $self->{'config'}{$server}{'readers'}{$reader}{$name}
            if exists $self->{'config'}{$server}{'readers'}{$reader}{$name};
    } else {
        $self->{'config'}{$server}{$name} = $value if defined $value;
        return $self->{'config'}{$server}{$name}
            if exists $self->{'config'}{$server}{$name};
    }

    return;
}

=head2 server

Returns the name of the currently selected datastore.

Accepts one option argument, which may be used to change the current datastore
selection. Note that simply calling this with a new datastore name does not
alter current DBIx::DataStore objects to switch their connections (unless
explicitly told to reconnect).

=cut

sub server {
    my ($self, $server) = @_;

    $self->{'server'} = $server
        if  defined $server
         && $server ne 'default'
         && exists $self->{'raw_config'}{$server};

    return $self->{'server'} if exists $self->{'server'};
    return;
}

# Internal Subs

=head2 find_config_file

Locates the DBIx::DataStore configuration file by looking in a predetermined
list of locations.

=cut

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

=head2 normalize_config

Given a raw structure read from a YAML configuration, this method will return a
hash reference that has all default values set (for anything the configuration
did not itself specify) and will also merge global config defaults, as well as
primary defaults to readers.

The structure returned may be safely (assuming it is not manipulated further)
used by any methods or functions that expect a valid configuration.

If this method cannot normalize the configuration properly, it will die.

=cut

sub normalize_config {
    my ($orig) = @_;

    # hold the normalized configuration we end up returning
    my %config;

    # check for a __default__ entry first, which can be used to set common
    # options for every datastore in the configuration
    my %default;

    if (exists $orig->{'__default__'}) {
        %default = %{thaw(freeze($orig->{'__default__'}))};
        delete $orig->{'__default__'};
    }

    my @server_opts = qw( driver host port database user password );

    foreach my $server (keys %{$orig}) {
        $config{$server} = {
            cache_connection => 0,
            cache_statements => 0,
            auto_commit      => 0,
        };

        # global options affecting the datastore
        foreach my $opt (keys %{$config{$server}}) {
            $config{$server}{$opt} = truthiness($default{$opt})
                if exists $default{$opt} && defined truthiness($default{$opt});

            $config{$server}{$opt} = truthiness($orig->{$server}{$opt})
                if exists $orig->{$server}{$opt}
                && defined truthiness($orig->{$server}{$opt});
        }

        $config{$server}{'default_reader'} =
              exists $orig->{$server}{'default_reader'} ? $orig->{$server}{'default_reader'}
            : exists $default{'default_reader'}         ? $default{'default_reader'}
            :                                             '__random__';

        $config{'primary'} = { schemas => ['public'] };
        $config{'readers'} = {};

        # primary server settings -- all writes get directed here
        if (exists $default{'primary'}) {
            foreach my $opt (@server_opts) {
                $config{$server}{'primary'}{$opt} = $default{'primary'}{$opt}
                    if exists $default{'primary'}{$opt};
            }
        }
        if (exists $orig->{$server}{'primary'}) {
            foreach my $opt (@server_opts) {
                $config{$server}{'primary'}{$opt} = $orig->{$server}{'primary'}{$opt}
                    if exists $orig->{$server}{'primary'}{$opt};
            }
        }

        # default schema search paths used, for those databases which have schemas
        # we support multiple notations:
        # - arrayref (preferred), where order is maintained when issuing set search_path
        #   (or equivalent for non-PG databases)
        # - hashref, where we put them in key-alphanumeric order
        # - alphanum-containing scalar, where it's just a single schema in the list
        # - everything else results in no search path (meaning it will default to
        #   whatever the database server chooses, based on its own rules/settings)
        if (exists $default{'primary'}{'schemas'}) {
            if (ref($default{'primary'}{'schemas'}) eq 'ARRAY') {
                $config{$server}{'primary'}{'schemas'} = [@{$default{'primary'}{'schemas'}}];
            } elsif (ref($default{'primary'}{'schemas'}) eq 'HASH') {
                $config{$server}{'primary'}{'schemas'} = [sort keys %{$default{'primary'}{'schemas'}}];
            } elsif ($default{'primary'}{'schemas'} =~ m{\w+}o) {
                $config{$server}{'primary'}{'schemas'} = [$default{'primary'}{'schemas'}];
            } else {
                $config{$server}{'primary'}{'schemas'} = [];
            }
        }
        if (exists $orig->{$server}{'primary'}{'schemas'}) {
            if (ref($orig->{$server}{'primary'}{'schemas'}) eq 'ARRAY') {
                $config{$server}{'primary'}{'schemas'} = [@{$orig->{$server}{'primary'}{'schemas'}}];
            } elsif (ref($orig->{$server}{'primary'}{'schemas'}) eq 'HASH') {
                $config{$server}{'primary'}{'schemas'} = [sort keys %{$orig->{$server}{'primary'}{'schemas'}}];
            } elsif ($orig->{$server}{'primary'}{'schemas'} =~ m{\w+}o) {
                $config{$server}{'primary'}{'schemas'} = [$orig->{$server}{'primary'}{'schemas'}];
            } else {
                $config{$server}{'primary'}{'schemas'} = [];
            }
        }

        # reader configuration
        # these servers can be used to offload read-only, non-transactional queries
        # to reduce the strain on the primary database, or to target specific
        # performance-tuning rdbms configurations for BI/OLAP purposes

        # unlike the primary config, we only check the global config (if one was
        # present) if the server config specifies one with the same name, which makes
        # it safer to define defaults for common reader databases without having
        # them show up unexpectedly in setups with many distinct datastores
        if (exists $orig->{$server}{'readers'} && ref($orig->{$server}{'readers'}) eq 'HASH') {
            foreach my $reader (keys %{$orig->{$server}{'readers'}}) {
                foreach my $opt (@server_opts) {
                    $config{$server}{'readers'}{$reader}{$opt} =
                        $default{'readers'}{$reader}{$opt}
                            if exists $default{'readers'}{$reader}{$opt};
                }
                foreach my $opt (@server_opts) {
                    $config{$server}{'readers'}{$reader}{$opt} =
                        $orig->{$server}{'readers'}{$reader}{$opt}
                            if exists $orig->{$server}{'readers'}{$reader}{$opt};
                }

                if (exists $default{'readers'}{$reader}{'schemas'}) {
                    if (ref($default{'readers'}{$reader}{'schemas'}) eq 'ARRAY') {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [@{$default{'readers'}{$reader}{'schemas'}}];
                    } elsif (ref($default{'readers'}{$reader}{'schemas'}) eq 'HASH') {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [sort keys %{$default{'readers'}{$reader}{'schemas'}}];
                    } elsif ($default{'readers'}{$reader}{'schemas'} =~ m{\w+}o) {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [$default{'readers'}{$reader}{'schemas'}];
                    } else {
                        $config{$server}{'readers'}{$reader}{'schemas'} = [];
                    }
                }
                if (exists $orig->{$server}{'readers'}{$reader}{'schemas'}) {
                    if (ref($orig->{$server}{'readers'}{$reader}{'schemas'}) eq 'ARRAY') {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [@{$orig->{$server}{'readers'}{$reader}{'schemas'}}];
                    } elsif (ref($orig->{$server}{'readers'}{$reader}{'schemas'}) eq 'HASH') {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [sort keys %{$orig->{$server}{'readers'}{$reader}{'schemas'}}];
                    } elsif ($orig->{$server}{'readers'}{$reader}{'schemas'} =~ m{\w+}o) {
                        $config{$server}{'readers'}{$reader}{'schemas'} =
                            [$orig->{$server}{'readers'}{$reader}{'schemas'}];
                    } else {
                        $config{$server}{'readers'}{$reader}{'schemas'} = [];
                    }
                }

                # if no reader-specific schemas were defined, inherit from the primary
                if (!exists $config{$server}{'readers'}{$reader}{'schemas'}) {
                    $config{$server}{'readers'}{$reader}{'schemas'} =
                        $config{$server}{'primary'}{'schemas'};
                }
            }
        }
    }

    return \%config;
}

sub pick_datastore {
    my ($self, $name) = @_;

    if (defined $name && $name ne 'default') {
        return $name if exists $self->{'config'}{$name};
        return;
    }
}

sub read_config {
    my ($path) = @_;

    return unless defined $path && -f $path && -r _;
    my $yaml = LoadFile($path);

    return unless defined $yaml && ref($yaml) eq 'HASH';
    return $yaml;
}

sub truthiness {
    my ($setting) = @_;

    return 0 unless defined $setting;
    return $setting if $setting == 0 || $setting == 1;
    return $setting =~ m{^\s*\d+(\.\d+)?\s*$}o && $setting < 1 ? 0 : 1;

    return 1 if $setting =~ m{^\s*(t|true|y|yes|on|enabled?)\s*$}oi;
    return 0 if $setting =~ m{^\s*(f|false|n|no|off|disabled?)\s*$}oi;

    return;
}

1;
