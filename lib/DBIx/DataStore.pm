package DBIx::DataStore;

use v5.10;
use strict;
use warnings;

use DBIx::DataStore::Config;
use DBIx::DataStore::Result::Set;

=head1 NAME

DBIx::DataStore - A lightweight Perl/DBI wrapper

=head1 VERSION

Version 0.099001

=cut

our $VERSION = '0.099001';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

DBIx::DataStore (hereafter referred to at times as "the module," "DS,"
and "DataStore") is a lightweight wrapper around Perl's DBI library. Its
primary aims are:

=over 4

=item * Simplify DSN configuration management

=item * Provide a much simpler method of dealing with placeholder values

=item * Simple and transparent distribution of read queries to a set of read-only replicating servers

=item * Offer a modest collection of convenience methods for transactions, result iteration, and so on

=back

DataStore does not provide any ORM like functionality. You are still
responsible for writing all your own SQL and mapping your application's
data to your database's schemas. Of course, you can wrap DataStore up in
to an ORM and simply use this module as the database interface layer.

A simple example of how one might go about using DBIx::DataStore:

    use DBIx::DataStore;

    my $db = DBIx::DataStore->new( $storename );

    my %newdata = ( moderator => 't', updated_at => 'now' );

    $db->begin;
    my $res = $db->do(q{
        update users
        set ???
        where id in ??? and not moderator
        returning id, name
    }, \%newdata, \@userids);

    unless ($res) {
        $db->rollback;
        die "Error marking users as moderators: " . $res->error;
    }

    while ($res->next) {
        printf("%s (%d) has been newly minted a moderator!\n",
            $res->{'name'}, $res->[0]);
    }

    $db->commit;

First, you create a new DB handler by specifying the datastore to which
you will connect (which may contain anywhere from 1 to N databases, with
one of them designated the primary RW database and the others acting as
read-only copies to which non-transactional SELECTs may be distributed).

Once connected, you optionally begin a transaction and start issuing
queries. In our example here, we are updating a users table to promote
some people to moderators. And here is shown one of the greatest
conveniences of DBIx::DataStore over your typical DBI usage patterns.
We have two placeholders in this query -- one is automatically
transformed from a hash reference to a "SET col1 = ?, col2 = ?"
and the other is an array reference which DataStore converts into the
proper "IN (?,?,...)" form for you.

Hash reference placeholders can
also be used for INSERT statements, where they will be transformed
into "(col1,col2) values (?,?)" or if you pass an array reference of
hash references (where the keys are the same in all the hashes), a
multi-row single statement INSERT will be created for you.

The query we've issued has a RETURNING clause, so we can also (after
checking for errors) iterate through the result set returned by the
database and print out the records provided. You may notice that as
we are advancing through the result set ($res here is both the entire
result set, as well as the current row of the iterator) that we can
access the fields returned by the query both by their name as if $res
were a simple hash reference, or as their position if it were an
array reference.

At the very end, we go ahead and commit the transaction after
displaying changes made to the user. You can continue to
use a result set object after comitting/rolling back the transaction
in which it was created (though you won't be able to guarantee the
values in $res reflect current reality at that point).

You may also maintain as many result set objects simultaneously as
you wish. Each call to $db->do will return a new result set object
that does not conflict with any of the others (except that you may
issue a query after another that changes the same data you retrieved
with the first).

=head1 METHODS

=head2 new

Connects to the primary database for the specified datastore, and
returns a new DBIx::DataStore object for that connection.

    my $db = DBIx::DataStore->new( $storename );

    ... or ...

    my $db = DBIx::DataStore->new({
        primary => {
            driver   => 'Pg',
            host     => 'localhost',
            user     => 'dbuser',
            password => 'secret',
        }
    });

If you have a YAML configuration present, you can simply specify
the name of the datastore you want. You may also pass a hash reference
instead of a datastore name, with a data structure that matches that
of the YAML configuration.

If you have a YAML configuration, and pass nothing to this method,
it will scan all of the datastore configurations for a match against
the "package" value(s) and this module's caller stack. The matches
will begin with the outermost caller entry, and alphabetically from
the YAML configuration. The first match will be used.

=cut

sub new {
    my ($class, $store) = @_;

    my $self = {};

    return bless $self, $class;
}

=head2 do

This is the real workhorse method, and the manner by which you issue
your queries to any connected databases. In its simplest form, it takes
a single scalar argument: your SQL query with no placeholders.

If your query uses any placeholders, those follow in a list after the
query itself. Non-scalar placeholders, such as a list of values for an
IN, or a hash for an UPDATE's SET, must be passed as references. All of
the placeholders' values must follow the query in the same order in which
the corresponding placeholders are used in the query.

An optional hashref argument may precede the query, as the first argument
to this method, which can provide a number of options. Features such as
pagination, explicit selection of reader databases, and so on are
controlled in this way.

=head3 Placeholders

Basic DBI placeholders function identically in DBIx::DataStore. You may
(and should!) paramaterize any scalar inputs to your query using a single
question mark in place of the value itself. The final value must then
be passed in as part of a list to the do() method after the query.

    my $res = $db->do(q{ select * from users where email = ? }, $email);

This will ensure that all (potentially user supplied) values in your
queries are properly handled and that you will not be susceptible to
SQL injection attacks.

But what if you have a list of email addresses and you want to get all
those users at once? With vanilla DBI, you have to count how many you
have, put together a sequence of question marks, interpolate that into
the SQL string in your code, and pass that list on to the execute()
method. With DBIx::DataStore, that work is hidden from you:

    my $res = $db->do(q{ select * from users where email in ??? }, \@emails);

Similarly, you can save yourself some work when it comes to UPDATEs:

    my $res = $db->do(q{ update users set ??? where id = ? },
        { name => $new_name, title => $title }, $user_id);

As well as INSERTs:

    my $res = $db->do(q{ insert into users ??? },
        { email => $email, name => $name, title => $title });

    my $res = $db->do(q{ insert into users ??? },
        [   { email => $email1, name => $name1, title => $title1 },
            { email => $email2, name => $name2, title => $title2 },
        ]);

Note that in the second example above, we are passing in an array
reference of hash references. That will cause two rows to be inserted
with that single database call (if your database supports that syntax).
The main caveat with this usage is that the column names used in the
insert are taken from only the first hash reference in the list.
DBIx::DataStore will expect those same key/value pairs to be present in
all hash references in the list, and will die if it finds any are
missing.

=head3 Pagination

DBIx::DataStore tries to make things easy if you're dealing with a
lot of results and want to display them in pages to your end user. To
this end, if you pass the options hashref before your query, you may
specify in it one or two of the following:

=over 4

=item * page

The (1-indexed, not 0) page of results to return with the result set
object. (Default: 1)

=item * per_page

How many rows to return per page. (Default: 25)

=back

As long as one or the other of those is specified, your query will be
modified as necessary to return only the relevant rows, and you will
be able to call the pager() method on your result set object (see
C<DBIx::DataStore::Result::Set> for details) to get details about
the current page, its neighbors, the total number of entries (all
pages), and so on.

If you pass only one option, the other will use its default value as
shown above. If you pass neither option, even if you do include the
optional hashref before your query, you will not receive paged results
and you will not be able to call the pager() method on your result set.

=head3 Reader/Server Selection

If you have more than one reader database configured for your
datastore, you can rely on the automatic (random) selection of
reader for your non-transactional SELECTs, or you can force a
specific server to be used. This option is also handy if you have
what appears to be a non-transactional SELECT, but which actually
calls a procedure or function which submits modifying DML to the
database, or even non-transactional selects that you just want to
guarantee are working with the most current data possible (if you
use an asynchronous replication system between your master and
reader databases).

    my $res = $db->do(
        { server => 'primary' },
        q{ select modifying_dml_procedure() });

    my $res = $db->do(
        { server => 'olap-1' },
        q{ select * from expensive_view });

=head3 Other Options

=over 4

=item * name

For logging purposes, you can pass in an arbitrary string (whitespace
will be condensed, newlines and such removed) that will be included
in all logging output related to the query. If you don't provide a
query name, a random one will be generated.

=back

=cut

sub do {
    my $self = shift;
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    my $query = shift;
    my @binds = @_;

    
}

=head1 AUTHORS

Jon Sime, C<< <jonsime at gmail.com> >>

Buddy Burden, C<< <barefootcoder at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dbix-datastore at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBIx-DataStore>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 TODO

=over 4

=item * Named placeholders

=back

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBIx::DataStore

You can find the latest revisions of this module at GitHub:

=over 4

L<https://github.com/jsime/dbix-datastore>

=back

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-DataStore>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBIx-DataStore>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBIx-DataStore>

=item * Search CPAN

L<http://search.cpan.org/dist/DBIx-DataStore/>

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Jon Sime, Buddy Burden.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
