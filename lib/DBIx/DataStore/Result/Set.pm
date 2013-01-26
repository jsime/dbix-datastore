package DBIx::DataStore::Result::Set;

use v5.10;
use strict;
use warnings;

use Data::Page;

use base 'DBIx::DataStore::Result::Row';

use overload (
    'bool'  =>  sub { !${$_[0]}->{'error'} },
);

sub all {
    my ($self) = @_;

    my $data = $$self->{'_sth'}->fetchall_arrayref();

    if ($$self->{'_sth'}->err) {
        die dslog("Encountered error when retrieving complete result set: " . $$self->{'_sth'}->errstr);
    }

    if ($data && @$data) {
        my $fields = [ @{ $$self->{'_sth'}->{'NAME'} } ];
        my $index = { %{ $$self->{'_sth'}->{'NAME_hash'} } };

        foreach (@$data) {
            $_ = DBIx::DataStore::Result::Row->new($fields, $index, $_);
        }
    }

    return $data;
}

sub error {
    return ${$_[0]}->{'error'};
}

sub next {
    my ($self) = @_;

    if (my $row = $$self->{'_sth'}->fetchrow_arrayref)
    {
        $$self->{'impl'}->[DBIx::DataStore::Result::Row::VALUES()] = $row;
        return $self;
    }
    return 0;
}

sub next_hashref {
    my ($self) = @_;

    return $self->hashref if $self->next;
    return 0;
}

sub page {
    my ($self) = @_;
}

sub pager {
    my ($self) = @_;

    my $p = Data::Page->new();

    $p->total_entries($self->count());
    $p->entries_per_page($$self->{'_page_per'});
    $p->current_page($$self->{'_page_num'});

    return $p;
}

sub count {
    my ($self) = @_;

    # Faster method when selects are the only things that get handled below
    return $$self->{'_rows'} unless $$self->{'_st_type'} eq 'select';

    # See if we've already been called before and stored the total number of rows
    if (defined $$self->{'_total_rows'} && $$self->{'_total_rows'} =~ /^\d+$/o) {
        return $$self->{'_total_rows'};
    }

    if ($$self->{'_sql'} =~ /^\s*select\s+count\(\s*[*]\s*\)\s+/ois) {
        if ($self && $self->next) {
            $$self->{'_total_rows'} = $self->[0];
            return $self->[0];
        }
    } else {
        # negative look-ahead tries to prevent warning when the limit is part of a subquery
        if ($$self->{'_sql'} =~ /\s+limit\s+\d+(?!.*[)])/oi) {
            dslog("Getting result set row count for a query that appears to have used a LIMIT clause. Eh... why not?")
                if DEBUG() >= 3;
        }

        my $query = "select count(*) from ( " . $$self->{'_sql'} . " ) derived";
        my $sth = $$self->{'_dbh'}->prepare($query)
            || die dslog("Error encountered preparing row count query: " . $$self->{'_dbh'}->errstr);
        $sth->execute(@{$$self->{'_binds'}})
            || die dslog("Error encountered executing row count query: " . $sth->errstr);

        my $row = $sth->fetchrow_arrayref || confess("Error retrieving row from database result: " . $sth->errstr);
        $$self->{'_total_rows'} = $row->[0];
        return $row->[0];
    }

    return;
}

1;
