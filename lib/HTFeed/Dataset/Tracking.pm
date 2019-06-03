package HTFeed::Dataset::Tracking;

use warnings;
use strict;

use HTFeed::VolumeGroup;

use Carp;
our @CARP_NOT;

use base qw(HTFeed::DBTools);
use HTFeed::DBTools qw(get_dbh);

our @EXPORT_OK = qw{tracking_delete tracking_add};

=item tracking_delete
mark $volume as deleted in dataset_tracking table

tracking_delete($volume);
=cut

sub tracking_delete{
    my $volume = shift;
    my $ns = $volume->get_namespace();
    my $id = $volume->get_objid();

    my $sth = get_dbh()->prepare(q{UPDATE feed_dataset_tracking SET delete_t = NOW() WHERE namespace = ? AND id = ? AND delete_t IS NULL;});
    $sth->execute($ns,$id);
}

=item tracking_add
add $volume to dataset_tracking table

tracking_delete($volume);
=cut

sub tracking_add{
    my $volume = shift;
    my $ns = $volume->get_namespace();
    my $id = $volume->get_objid();

    my $version_t = $volume->zip_date();

    my $sth = get_dbh()->prepare(q{INSERT INTO feed_dataset_tracking (namespace,id,version) VALUES (?,?,?) ON DUPLICATE KEY UPDATE delete_t = NULL, version = ?;});
    $sth->execute($ns,$id,$version_t,$version_t);
}

=item get_outdated
return arrayref of volumes that need to be updated

get_outdated();

=caveats

This forks. Think about that when you are calling this from other code that forks.

=cut

sub get_outdated{
	## TODO: -3600 is a hack so we don't reingest everything. Verison used to be from the METS (and still is for old volumes), now it's zip_date. Remove -3600 hack once transition is complete.
    my $sth = get_dbh()->prepare(q{SELECT namespace,id FROM feed_dataset_tracking NATURAL LEFT JOIN feed_audit WHERE delete_t IS NULL AND version - zip_date < -3600;});
    #my $sth = get_dbh()->prepare(q{SELECT namespace,id FROM feed_dataset_tracking NATURAL LEFT JOIN feed_audit WHERE delete_t IS NULL AND version < zip_date;});
    $sth->execute();

	my $ns_objids = $sth->fetchall_arrayref();

	return HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
}

sub get_all {
    my $sth = get_dbh()->prepare(q{SELECT namespace,id FROM feed_dataset_tracking WHERE delete_t IS NULL ORDER BY namespace, id;});
    $sth->execute();

	my $ns_objids = $sth->fetchall_arrayref();

	return HTFeed::VolumeGroup->new(ns_objids=>$ns_objids);
}

__END__
