package DBIx::DataStore::Log;

use 5.010;
use strict;
use warnings;

sub new {
    my ($class, $opts) = @_;

    $opts = {} unless $opts && ref($opts) eq 'HASH';

    my $self = {
        trace       => 0,
        level       => 'CRITICAL',
        level_order => [qw( CRITICAL ERROR WARN INFO DEBUG )],
        levels      => {},
        format      => '[TS] [PID] [LEVEL] [DATASTORE] [QUERY] MSG',
    };

    for (0..$#{$self->{'level_order'}}) {
        $self->{'levels'}{ $self->{'level_order'}[$_] } = $_;
    }

    die "Invalid default logging level defined." unless exists $self->{'levels'}{$self->{'level'}};

    $self->{'trace'} = 1 if $opts->{'trace'} && $opts->{'trace'} == 1;

    return bless $self, $class;
}

sub level {
    my ($self, $level) = @_;

    return unless defined $level;
    return unless $self->level(uc($level));

    $self->{'level'} = uc($level);

    return $self->level;
}

sub level_num {
    my ($self, $level) = @_;

    if (defined $level) {
        return $self->{'levels'}{$level} if defined $self->{'levels'}{$level};
        return;
    }

    return $self->{'levels'}{$self->{'level'}};
}

sub log {
    my $self = shift;
    my $level = uc(shift) || 'ERROR';

    die "Invalid logging level specified: $level" unless $self->level_num($level);

    # Short circuit if the incoming message is a higher logging level than
    # what we're currently set to log.
    return if $self->level_num($level) > $self->level_num;

    my @messages = @_;

    my @callstack = caller();
}

sub trace {
    my ($self, $value) = @_;

    $self->{'trace'} = $value if defined $value && ($value == 0 || $value == 1);

    return $self->{'trace'};
}

1;
