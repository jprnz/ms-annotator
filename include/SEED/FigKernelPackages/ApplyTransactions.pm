#!/usr/bin/perl -w
#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#


package ApplyTransactions;

    use TransactionProcessor;
    @ISA = ('TransactionProcessor');

    use strict;
    use Tracer;
    use PageBuilder;
    use FIG;

=head1 Apply Transactions

=head2 Introduction

This is a TransactionProcessor subclass that applies the transaction changes to
the FIG data store.

=head2 Methods

=head3 new

    my $xprc = ApplyTransactions->new(\%options, $command, $directory, $idFile);

Construct a new ApplyTransactions object.

=over 4

=item options

Reference to a hash table containing the command-line options.

=item command

Command specified on the B<TransactFeatures> command line. This command determines
which TransactionProcessor subclass is active.

=item directory

Directory containing the transaction files.

=item idFile

Name of the ID file (if needed).

=back

=cut

sub new {
    # Get the parameters.
    my ($class, $options, $command, $directory, $idFile) = @_;
    # Construct via the subclass.
    return TransactionProcessor::new($class, $options, $command, $directory, $idFile);
}

=head3 Setup

    $xprc->Setup();

Set up to apply the transactions. This includes reading the ID file.

=cut
#: Return Type ;
sub Setup {
    # Get the parameters.
    my ($self) = @_;
    # Read the ID hash from the ID file.
    $self->ReadIDHash();
    # Memorize the user ID we want to use for the annotations.
    $self->{user} = "master:automated_assignments";
    # Insure the subsystems are properly indexed.
    FIG::run("index_subsystems");
}

=head3 SetupGenome

    $xprc->SetupGenome();

Set up for processing this genome.

=cut
#: Return Type ;
sub SetupGenome {
    # Get the parameters.
    my ($self) = @_;
    my $fig = $self->FIG();
    # If we're in safe mode, start a database transaction.
    if ($self->Option("safe")) {
        $fig->db_handle->begin_tran();
    }
    # If we're producing a TBL file, open it.
    if ($self->Option("tlbFiles")) {
        my $fileName = $self->CurrentFileName() . ".tbl";
        Open(\*TBLFILE, ">$fileName");
    }
}

=head3 TeardownGenome

    $xprc->TeardownGenome();

Clean up after processing this genome. This involves optionally committing any updates.

=cut
#: Return Type ;
sub TeardownGenome {
    # Get the parameters.
    my ($self) = @_;
    my $fig = $self->FIG();
    # If we're in safe mode, commit the database transaction.
    if ($self->Option("safe")) {
        $fig->db_handle->commit_tran();
    }
    # If we're producing a TBL file, open it.
    if ($self->Option("tlbFiles")) {
        close TBLFILE;
    }
}

=head3 Add

    $xprc->Add($newID, $locations, $translation);

Add a new feature to the data store.

=over 4

=item newID

ID to give to the new feature.

=item locations

Location of the new feature, in the form of a comma-separated list of location
strings in SEED format.

=item translation (optional)

Protein translation string for the new feature. If this field is omitted and
the feature is a peg, the translation will be generated by normal means.

=back

=cut

sub Add {
    my ($self, $newID, $locations, $translation) = @_;
    my $fig = $self->{fig};
    # Extract the feature type and ordinal number from the new ID.
    my ($ftype, $ordinal, $key) = $self->ParseNewID($newID);
    # Add the new feature.
    my $realID = $self->AddFeature($ordinal, $key, $ftype,
                            $locations, "", $translation);
    Trace("Feature $realID added for pseudo-ID $newID.") if T(4);
    # Create the annotation.
    my $message = "New gene predicted based on similarity to putative genes in closely-related genomes";
    $fig->add_annotation($realID, $self->{user}, $message);
    # If we're producing a TBL file, write out a transaction.
    if ($self->Option("tblFiles")) {
        print TBLFILE "ADD\$realID\t$locations\t$translation\n";
    }

}

=head3 Change

    $xprc->Change($fid, $newID, $locations, $aliases, $translation);

Replace a feature to the data store. The feature will be marked for deletion and
a new feature will be put in its place.

This is a much more complicated process than adding a feature. In addition to
the add, we have to create new aliases (or copy over the old ones) and transfer
across the assignment, subsystem linkages, and the annotations.

=over 4

=item fid

ID of the feature being changed.

=item newID

New ID to give to the feature.

=item locations

New location to give to the feature, in the form of a comma-separated list of location
strings in SEED format.

=item aliases (optional)

A new list of alias names for the feature.

=item translation (optional)

New protein translation string for the feature. If this field is omitted and
the feature is a peg, the translation will be generated by normal means.

=back

=cut

sub Change {
    my ($self, $fid, $newID, $locations, $aliases, $translation) = @_;
    my $fig = $self->{fig};
    # Extract the feature type and ordinal number from the new ID.
    my ($ftype, $ordinal, $key) = $self->ParseNewID($newID);
    # Here we can go ahead and change the feature. First, we must
    # get the old feature's assignment and annotations. Note that
    # for the annotations we ask for the time in its raw format.
    my @functions = $fig->function_of($fid);
    my @annotations = $fig->feature_annotations($fid, 1);
    # Create some counters.
    my ($assignCount, $annotateCount, $attributeCount) = (0, 0, 0);
    # Check for aliases.
    if (! $aliases) {
        # The user didn't provide any, so we need to copy the old feature's
        # aliases.
        $aliases = $fig->feature_aliases($fid);
    }
    # Add the new version of the feature and get its ID.
    my $realID = AddFeature($self, $ordinal, $key, $ftype, $locations,
                            $aliases, $translation);
    # Copy over the assignments.
    for my $assignment (@functions) {
        my ($user, $function) = @{$assignment};
        $fig->assign_function($realID, $user, $function);
        $assignCount++;
    }
    # Copy over the annotations.
    for my $annotation (@annotations) {
        my ($oldID, $timestamp, $user, $annotation) = @{$annotation};
        $fig->add_annotation($realID, $user, $annotation, $timestamp);
        $annotateCount++;
    }
    # Copy over the attributes.
    my @attributes = $fig->get_attributes($fid);
    # Loop through the attributes, adding them to the replacement feature.
    for my $attribute (@attributes) {
        # The attribute descriptor is actually a four-tuple.
        my ($oldID, $key, $value, $url) = @{$attribute};
        # Add the attribute.
        $fig->add_attribute($realID, $key, $value, $url);
        $attributeCount++;
    }
    # Fix up the subsystems.
    $self->FixSubsystems($fid, $realID);
    # Mark the old feature for deletion.
    $fig->delete_feature($fid);
    # Write out the transaction.
    if ($self->Option("tblFiles")) {
        print TBLFILE "CHANGE\t$fid\t$realID\t$locations\t$aliases\t$translation\n";
    }
    # Tell the user what we did.
    $self->{stats}->Add("assignments", $assignCount);
    $self->{stats}->Add("annotations", $annotateCount);
    $self->{stats}->Add("attributes", $attributeCount);
    Trace("Feature $realID created from $fid. $assignCount assignments, $attributeCount attributes, and $annotateCount annotations copied.") if T(4);
    # Create the annotation.
    my $message = "Derived from $fid by changing the location to $locations.";
    $fig->add_annotation($realID, $self->{user}, $message);
}

=head3 Delete

    $xprc->Delete($fid);

Delete a feature from the data store. The feature will be marked as deleted,
which will remove it from consideration by most FIG methods. A garbage
collection job will be run later to permanently delete the feature.

=over 4

=item fid

ID of the feature to delete.

=back

=cut

sub Delete {
    my ($self, $fid) = @_;
    my $fig = $self->{fig};
    # Extract the feature type and count it.
    my $ftype = FIG::ftype($fid);
    $self->{stats}->Add($ftype, 1);
    # Fix up the subsystems.
    $self->FixSubsystems($fid);
    # Mark the feature for deletion.
    $fig->delete_feature($fid);
    # Write out the transaction.
    if ($self->Option("tlbFiles")) {
        print TBLFILE "DELETE\t$fid\n";
    }
}

=head3 FixSubsystems

    $sfx->FixSubsystems($fid, $newID);

Remove the specified feature from all subsystems. If the feature is being replaced
by a new feature, the specified new feature will be added in the old feature's place.

=over 4

=item fid

ID of the feature to be deleted.

=item newID (optional)

ID of the new feature replacing the old one, if any. This should be a real ID, not a
pseudo-ID.

=back

=cut

sub FixSubsystems {
    # Get the parameters.
    my ($self, $fid, $newID) = @_;
    my $fig = $self->FIG();
    # Get the genome ID.
    my $genomeID = $self->GenomeID();
    # Get the incoming PEG's subsystems.
    my @subsystems = $fig->subsystems_for_peg($fid);
    for my $pair (@subsystems) {
        # The subsystem tuple contains a subsystem name and a role.
        my ($subsysName, $role) = @{$pair};
        # Get the subsystem and retrieve the PEGs from the appropriate cell.
        # Note we have to be careful, since the subsystem methods fail if
        # the data is bad.
        my $subsystem = $fig->get_subsystem($subsysName);
        my @pegsInCell;
        my $working = 0;
        eval {
             @pegsInCell = $subsystem->get_pegs_from_cell($genomeID, $role);
             $working = 1;
        };
        # Only proceed if we found the cell.
        if ($working) {
            Trace("Role $role returned (" . join(", ", @pegsInCell) . ").") if T(4);
            # Delete the incoming PEG.
            my @newPegsInCell = grep { $_ ne $fid } @pegsInCell;
            # If there's a replacement PEG, add it.
            push @newPegsInCell, $newID;
            # Update the subsystem.
            eval {
                $subsystem->set_pegs_in_cell($genomeID, $role, \@newPegsInCell);
            };
            $subsystem->write_subsystem();
            $self->IncrementStat("subsystems");
        }
    }
}

=head3 AddFeature

    my $realID = $self->AddFeature($ordinal, $key, $ftype, $locations, $aliases, $translation);

Add the specified feature to the FIG data store. This involves generating the new feature's
ID, creating the translation (if needed), and adding the feature to the data store. The
generated ID will be returned to the caller.

=over 4

=item ordinal

Zero-based ordinal number of the proposed feature in the ID space. This is added to the
base ID number to get the real ID number.

=item key

Key to use for getting the base ID number from the ID hash.

=item ftype

Proposed feature type (C<peg>, C<rna>, etc.)

=item locations

Location of the new feature, in the form of a comma-separated list of location
strings in SEED format.

=item aliases (optional)

A new list of alias names for the feature.

=item translation (optional)

Protein translation string for the new feature. If this field is omitted and
the feature is a peg, the translation will be generated by normal means.

=back

=cut

sub AddFeature {
    # Get the parameters.
    my ($self, $ordinal, $key, $ftype, $locations, $aliases, $translation) = @_;
    my $fig = $self->{fig};
    # We want to add a new feature using the information provided. First, we
    # generate its ID.
    my $retVal = $self->GetRealID($ordinal, $key);
    # Next, we insure that we have a translation.
    my $actualTranslation = $self->CheckTranslation($ftype, $locations,
                                                    $translation);
    # Now we add it to FIG.
    $fig->add_feature($self->{genomeID}, $ftype, $locations, $aliases,
                      $actualTranslation, $retVal);
    # Append it to the NR file.
    Open(\*FASTANR, ">>$FIG_Config::global/nr");
    FIG::display_id_and_seq($retVal, \$actualTranslation, \*FASTANR);
    close FASTANR;
    # Tell FIG to recompute the similarities.
    $fig->enqueue_similarities([$retVal]);
    # Return the ID we generated.
    return $retVal;
}

1;