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


package FudgeTransactions;

    use TransactionProcessor;
    @ISA = ('TransactionProcessor');

    use strict;
    use Tracer;
    use PageBuilder;
    use FIG;

=head1 Fudge Transactions

=head2 Introduction

This is a TransactionProcessor subclass that creates test data from transactions
that have already been applied. Each ADD is converted into an ADD and a DELETE,
and each CHANGE is updated to use the new ID. Note that the ID file will need to
be modified before the transactions can be applied.

=head2 Methods

=head3 new

    my $xprc = FudgeTransactions->new(\%options, $command, $directory, $idFile);

Construct a new FudgeTransactions object.

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
}


=head3 Teardown

    $xprc->Teardown();

Update the ID table with high numbers to avoid duplication.

=cut
#: Return Type ;
sub Teardown {
    # Get the parameters.
    my ($self) = @_;
    # Get the ID hash.
    my $idHash = $self->IDHash;
    # Loop through the ID hash, creating a new ID file.
    my $countFile = $self->IDFileName;
    Open(\*COUNTFILE, ">$countFile");
    print "\nTable of Counts\n";
    for my $idKey (keys %{$idHash}) {
        $idKey =~ /^(\d+\.\d+)\.([a-z]+)$/;
        my ($org, $ftype) = ($1, $2);
        print COUNTFILE "$org\t$ftype\t9000\n";
    }
    close COUNTFILE;
    Trace("ID file $countFile updated.") if T(2);
}

=head3 SetupGenome

    $xprc->SetupGenome();

Set up for processing this genome. This opens the output file.

=cut
#: Return Type ;
sub SetupGenome {
    # Get the parameters.
    my ($self) = @_;
    my $fig = $self->FIG();
    # Create the output file for this genome.
    my $fileBase = $self->CurrentFileName;
    Open(\*TRANSOUT, ">$fileBase.tbl");
}

=head3 TeardownGenome

    $xprc->TeardownGenome();

Clean up after processing this genome. This involves closing the output file and
doing a rename.

=cut
#: Return Type ;
sub TeardownGenome {
    # Get the parameters.
    my ($self) = @_;
    my $fig = $self->FIG();
    # Close the transaction output file.
    close TRANSOUT;
    # Rename the files.
    my $fileBase = $self->CurrentFileName;
    my $nameBase = $fileBase;
    if ($fileBase =~ m!/(.*)$!) {
        $nameBase = $1;
    }
    my $okFlag = rename($fileBase, "$nameBase.bak");
    $okFlag = rename("$fileBase.tbl", $nameBase);
}

=head3 Add

    $xprc->Add($newID, $locations, $translation);

Add a new feature to the data store. The Add is transmitted unmodified to the
output file and then a delete is created for the ID added the last time.

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
    # Echo the add to the output file.
    print TRANSOUT "ADD\t$newID\t$locations\t$translation\n";
    # Extract the feature type and ordinal number from the new ID.
    my ($ftype, $ordinal, $key) = $self->ParseNewID($newID);
    # Get the real version of the new ID.
    my $realID = $self->GetRealID($ordinal, $key);
    # Create the delete command.
    print TRANSOUT "DELETE\t$realID\n";
}

=head3 Change

    $xprc->Change($fid, $newID, $locations, $aliases, $translation);

Replace a feature to the data store. The feature will be marked for deletion and
a new feature will be put in its place.

We change this so that it replaces the original real ID.

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
    # Get the real version of the new ID.
    my $realID = $self->GetRealID($ordinal, $key);
    # Create the change command.
    print TRANSOUT "CHANGE\t$realID\t$newID\t$locations\t$aliases\t$translation\n";
}

1;
