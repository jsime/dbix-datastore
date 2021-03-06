package DBIx::DataStore::Log;

use 5.010;
use strict;
use warnings;

use Data::Dumper;
use Time::HiRes;

=head1 NAME

DBIx::DataStore::Log

=head1 SYNOPSIS

DataStore's internal error/warning logging library. This module will handle
logging to a destination configured in the DataStore configuration, and may
be configured to log to different destinations for individual datastores.

It currently only handles logging to STDERR. Other destinations are planned
(direct to file, syslog, etc.) but not yet implemented.

=head1 EXAMPLE

    my $logger = DBIx::DataStore::Log->new({ trace => 1 });
    $logger->level('WARN');
    $logger->log('ERROR', 'Database connection failed.' . $db->error());

=head1 METHODS

=head2 new

Accepts: Optional hash reference to override default settings.

Returns: DBIx::DataStore::Log object.

Default options which may be overridden:

=over 4

=item * level

Default: 'CRITICAL'

Scalar containing the name of the minimum severity of a message for it
to appear in the logs. Current choices are: DEBUG, INFO, WARN, ERROR,
and CRITICAL in ascending order of severity.

=item * trace

Default: 0

Include stack traces in logging output. This will greatly increase the
amount of logging output you see, particularly if you set your logging
level broadly ({trace=>1, level=>'DEBUG', show_sql=>1, show_vars=>1} can
be a great way to fill up your log disks quickly).

=item * show_sql

Default: 0

When set to a true value, will cause error logging to include the SQL
query being executed (when appropriate; e.g. a DBIx::DataStore->new()
call which produces output has no SQL to log, and as such will not be
impacted by the value of this option).

=item * show_vars

Default: 0

When both this and C<show_sql> above are set to true values, logging
output will include not only the SQL query, when appropriate, but also
all bind variables associated with the invocation of the query that
triggered the logging output. It does not truncate or mask any of the
values, so use this with caution if your queries include sensitive
information, or you do things like multi-row bulk INSERTs. If this
option is set to true, but show_sql is false, it will have no effect.
Both must be turned on (and both default to off).

=back

=cut

sub new {
    my ($class, $opts) = @_;

    $opts = {} unless $opts && ref($opts) eq 'HASH';

    my $self = {
        trace       => 0,
        show_sql    => 0,
        show_vars   => 0,
        level       => 'CRITICAL',
        level_order => [qw( CRITICAL ERROR WARN INFO DEBUG )],
        levels      => {},
    };

    for (0..$#{$self->{'level_order'}}) {
        $self->{'levels'}{ $self->{'level_order'}[$_] } = $_;
    }

    die "Invalid default logging level defined." unless exists $self->{'levels'}{$self->{'level'}};

    $self->{'trace'} = 1 if $opts->{'trace'} && $opts->{'trace'} == 1;

    return bless $self, $class;
}

=head2 level ( $new_level )

Accepts: Optional scalar with new logging level name.

Returns: Scalar with current value name.

Mutator/accessor for the Log object's logging level. Except on error, will return
the Log object's current logging level name as a scalar value. Optional argument
must be a scalar value containing the name of a valid logging level (see the
section for the new() constructor for valid levels).

=cut

sub level {
    my ($self, $level) = @_;

    if (defined $level) {
        return unless $self->severity(uc($level));

        $self->{'level'} = uc($level);
    }

    return $self->{'level'};
}

=head2 severity ( $level )

Accepts: Optional scalar with logging level name.

Returns: Numeric severity.

With no arguments, returns the numeric severity of the current logger object.
With an argument, returns the numeric severity of that named logging level.
The numeric value begins with 0 being the most critical (e.g. errors which will
cause DBIx::DataStore to issue a die()) and 0+N being increasingly less
severe message levels.

While that might seem backwards, it allows you to rely on die()-calling errors
to always be the severity value 0, regardless of any changes to the list of
logging levels in future versions of the module. Whether that actually ever
makes a difference in a developer's use of this library remains to be seen.

=cut

sub severity {
    my ($self, $level) = @_;

    if (defined $level) {
        return $self->{'levels'}{$level} if defined $self->{'levels'}{$level};
        return;
    }

    return $self->{'levels'}{$self->{'level'}};
}

=head2 log ( [$sth,] $level, @messages )

Accepts: Minimum two arguments: first a scalar of the named logging level, second
(and any after that) the log messages to be printed to the configured destination.
An optional DBIx::DataStore::Result::Set object may also be passed in as the very
first argument. This is required if you hope to have any chance of getting the
SQL query and bind variables into the logging output.

Returns: In the case of severity==0 messages, DBIx::DataStore will call die() and
thus not return anything. All other levels will result in a true value being
returned if logging was successful and an undefined value returned otherwise.

This method will accept one-or-more messages to be printed out to the logging
destination. In the case of STDERR, files, or similar destinations, each message
will be printed on a separate line.

=cut

sub log {
    my $self = shift;
    my $sth = shift if ref($_[0]) eq 'DBIx::DataStore::Result::Set';
    my $level = uc(shift) || 'ERROR';

    die "Invalid logging level specified: $level" unless $self->severity($level);

    # Short circuit if the incoming message is a higher logging level than
    # what we're currently set to log.
    return if $self->severity($level) > $self->severity;

    # We'll only produce logging output if there was a message to log, or stack
    # trace output has been requested.
    my @messages = grep { defined $_ && $_ =~ m{\w}o } @_;
    return unless scalar(@messages) > 0 || $self->trace;

    my $ds_name = $self->datastore->name;
    my $query_name = defined $sth ? $sth->name : random_query_name();

    if ($self->show_sql && defined $sth) {
        push(@messages, 'SQL QUERY', '='x72, split(/\n/o, $sth->sql));

        if ($self->show_vars) {
            my $dumper = Data::Dumper->new([$sth->binds]);
            $dumper->Terse(1)->Indent(0)->Pad(' ');

            push(@messages, 'BIND VARIABLES', '='x72, $dumper->Dump);
        }
    }

    if ($self->trace) {
        push(@messages, 'STACK TRACE', '='x72);

        my $i = 0;
        while (my @stack = caller($i)) {
            push(@messages, sprintf('  {%d} %s,%d  %s::%s', $i, @stack[1,2,0,3]));
        }
    }

    my $timestamp = scalar(localtime);

    @messages = map {
            sprintf('[%s] [%d] [%s] [%s] [%s] %s',
                $timestamp, $$, uc($level), $ds_name, $query_name, $_
            )
        } @messages;

    print STDERR join("\n", @messages);

    # TODO make this more useful.
    die "See log for details." if $self->severity == 0;
    return 1;
}

=head2 random_query_name ()

Accepts: Nothing.

Returns: String containing query name.

Provides a randomly-generated name for logging purposes when the caller has not
provided a name for the query themselves.  Allows multiple log lines to be
easily identified as related.

=cut

sub random_query_name {
    my $name = 'DS' . time();

    return $name;
}

=head2 show_sql ( $boolean )

Accepts: Optional boolean to change show_sql option.

Returns: Current show_sql setting (1 or 0).

=cut

sub show_sql {
    my ($self, $value) = @_;

    $self->{'show_sql'} = $value if defined $value && ($value == 0 || $value == 1);
    return $self->{'show_sql'};
}

=head2 show_vars ( $boolean )

Accepts: Optional boolean to change show_vars option.

Returns: Current show_vars setting (1 or 0).

=cut

sub show_vars {
    my ($self, $value) = @_;

    $self->{'show_vars'} = $value if defined $value && ($value == 0 || $value == 1);
    return $self->{'show_vars'};
}

=head2 trace ( $boolean )

Accepts: Optional boolean to change trace option.

Returns: Current trace setting (1 or 0).

Mutator/accessor for the Log object's trace setting. Except on error, will return
the Log object's current trace setting name as a scalar value. Optional argument
must be a true or false scalar to change the Log object's trace setting.

=cut

sub trace {
    my ($self, $value) = @_;

    $self->{'trace'} = $value if defined $value && ($value == 0 || $value == 1);
    return $self->{'trace'};
}

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Jon Sime, Buddy Burden.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
