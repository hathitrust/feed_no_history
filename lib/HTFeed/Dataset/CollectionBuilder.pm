package HTFeed::Dataset::CollectionBuilder;

use warnings;
use strict;
use Carp;

use HTFeed::Config;

use base qw(HTFeed::DBTools);

sub get_volumes {
    my $collection = shift;

    my $collection_table = 'mb_coll_item';
    my $sth = HTFeed::DBTools::get_dbh()->prepare("SELECT extern_item_id FROM $collection_table where MColl_ID = ?");    
    $sth->execute($collection);

    my $rows = $sth->fetchall_arrayref();
    my @htids = map { @$_ } @{$rows};

	return HTFeed::VolumeGroup->new(htids=>\@htids);
}

1;

__END__

=description

    get a VolumeGroup from a Collection Builder collection

=cut
