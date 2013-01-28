package DBIx::DataStore::Result::Row::impl;

use 5.010;
use strict;
use warnings;

use constant INDEX  => 0;
use constant KEYS   => 1;
use constant VALUES => 2;
use constant ITER   => 3;

sub TIEHASH {
    bless [ $_[2], $_[1], $_[3], 0 ], $_[0];
}

sub FETCH {
    return exists $_[0]->[INDEX]->{$_[1]}
        ? $_[0]->[VALUES]->[ $_[0]->[INDEX]->{$_[1]} ]
        : die dslog("Invalid column name specified: $_[1]");
}

sub STORE {
    exists $_[0]->[INDEX]->{$_[1]}
        ? ($_[0]->[VALUES]->[ $_[0]->[INDEX]->{$_[1]} ] = $_[2])
        : die dslog("Cannot store to invalid column name: $_[1]");
}

sub DELETE {
    die dslog("Cannot delete columns from result set rows!");
}

sub EXISTS {
    return exists $_[0]->[INDEX]->{$_[1]};
}

sub FIRSTKEY {
    $_[0]->[ITER] = 0;
    NEXTKEY($_[0]);
}

sub NEXTKEY {
    return $_[0]->[KEYS]->[ $_[0]->[ITER]++ ] if $_[0]->[ITER] < @{ $_[0]->[KEYS] };
    return undef;
}

package DBIx::DataStore::Result::Row;

use strict;
use warnings;

use constant INDEX  => DBIx::DataStore::Result::Row::impl::INDEX;
use constant KEYS   => DBIx::DataStore::Result::Row::impl::KEYS;
use constant VALUES => DBIx::DataStore::Result::Row::impl::VALUES;
use constant ITER   => DBIx::DataStore::Result::Row::impl::ITER;

use overload (
    '%{}' => sub { ${$_[0]}->{'hash'} },
    '@{}' => sub { ${$_[0]}->{'impl'}->[VALUES] },
    '""'  => sub { 'Result::Row:' . (@{$_[0]} ? join('||', @{$_[0]}) : '') },
);

our $AUTOLOAD;
sub AUTOLOAD {
    my ($method) = $AUTOLOAD =~ /::(\w+)$/o;
    return if $method eq 'DESTROY';

    my ($self) = @_;

    if (ref($self) eq 'DBIx::DataStore::Result::Row' || ref($self) eq 'DBIx::DataStore::Result::Set') {
        return exists $$self->{'hash'}->{$method}
            ? $$self->{'hash'}->{$method}
            : die dslog("No such method (or column): $method");
    } else {
        die dslog("No such class method: $method");
    }
}

sub new {
    my $self = \{};
    my %tied_hash;
    $$self->{'impl'} = tie %tied_hash, $_[0] . '::impl', $_[1], $_[2], $_[3];
    $$self->{'hash'} = \%tied_hash;

    return bless($self, $_[0]);
}

sub col {
    my ($self, $id) = @_;

    return $id =~ /^\d+$/o ? $self->[$id] : $self->{$id};
}

sub columns {
    my ($self) = @_;

    return @{ $$self->{'impl'}->[KEYS] };
}

sub hashref {
    my ($self) = @_;

    return { map { $_ => $$self->{'hash'}->{$_} } @{ $$self->{'impl'}->[KEYS] } };
}

1;
