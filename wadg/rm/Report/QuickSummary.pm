############################################################
#
# Module: wadg::rm::Report::QuickSummary
#
# Created: 19.June.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
############################################################
package wadg::rm::Report::QuickSummary;
use strict;

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.0 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw( wadg::rm::Report );
} # end BEGIN
# non-exported package globals go here
use vars      qw( $CONFIG $GLOBALS $LANG $FORMATTER );


############################
## The object constructor ##
############################
# The Quick Summay inserts itself into the report page 
# (if all reports are on one page) and the navigation page.
# Therefore it is imperative that the report file and navigation 
# file are closed before this object is created. Otherwise 
# you will get file access errors.
sub new {
	my $self = {};
	my $proto = shift;
	my %parms = @_;
	my $class = ref($proto) || $proto;

	bless ($self, $class);
	$self->{_summaries} = {};
	$self->_initialize( %parms ) or return;

	# Setup caps rows and remove any double '_'
	$self->{_CONFIG}{$self->{token}}{Rows} =~ s/([A-Z0-9])/$1_/g;
	$self->{_CONFIG}{$self->{token}}{Rows} =~ s/__/_/g;
	
	
	return $self;
} # end new

##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: process
#
# Args: @data
#	@data	The data columns in the report line
#
# Description: Processes teh entire quic summary report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb28 Uses $shadedRow so alternating works, even if 
#           all reports aren't printed.                   JW
# 1999Mar09 Reads rows from config and builds summaries 
#           from %biggest hash.                           JW
# 2000Jun19 Converted to a class. Pulled out file stuff.  JW
# ----------------------------------------------------------
sub process {
	my $self = shift;

	#
	# Print a summary report for each report requested
	#
	my $totalCount = 1;
	my $ac = substr($self->{_CONFIG}{reports}{Active_Column}, 0, 1);
	if( $ac =~ /R/i ) {
		$totalCount = $self->{_GLOBALS}{SR};
	} elsif( $ac =~ /P/i ) {
		$totalCount = $self->{_GLOBALS}{PR};
	} elsif( $ac =~ /B/i ) {
		$totalCount = $self->{_GLOBALS}{BT};
	} # end if

	#
	# Run through summary rows in the order specified in the settings
	#
	my $section;
	foreach $section ( split( /[\s\b,;:]+/, $self->{_CONFIG}{$self->{token}}{Rows} ) ) {
		# Get the section's field name
		my( $field ) = split /[\012\015]+/, $self->{_CONFIG}{$section}{ShortName};
		if( defined $self->{_summaries}{$field}{max}{$ac} ) {
			# Swap shaded rows
			$self->{_shaded_row} = 1 - $self->{_shaded_row};
	
			# Output the table row
			$self->_data_row( $self->{_CONFIG}{$section}{MostActive}, 
			                  $self->{_summaries}{$field}{max}{name}, 
			                  $self->{_summaries}{$field}{max}{$ac},
			                  $self->{_FORMATTER}->getPercent( $self->{_summaries}{$field}{max}{$ac}, $totalCount )
			                );
		} # end if
	} # end foreach

} # end process



# ----------------------------------------------------------
# Sub: openReportFile
#
# Args: $filename
#		$filename	A filename to open and write to
#		$header  	An optional header to put at the top of the file
#
# Returns: An HTMLWriter object that will be used to write the 
# rest of the report content and should be closed with 
# closeReportFile. Returns undef on error.
#
# Description: Opens an output file for the quick summary, using 
# the current output file (inserting content) or creating a new 
# one through wadg::rm::Report::openReportFile.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Jun19 Created method from quicksummary sub.         JW
# 2000Sep20 Fixed bug in reference to $CONFIG             JW
# 2000Oct17 Fixed bug in file building                    JW
# ----------------------------------------------------------
sub openReportFile {
	my( $fileName ) = @_;
	local *reportFile;
	
	#
	# Read in the file contents
	#

	# Get existing file contents
	unless( open(reportFile,"<$fileName") ) {
		wadg::Errors::error( -1, 'E0001', $fileName );
	} # end unless
	my $temp_lines = join( '', <reportFile> );
	close reportFile;

	# Start replacing contents
	unless( open( reportFile,">$fileName" ) ) {
		wadg::Errors::error( -1, 'E0003', $fileName );
	} # end if
	return undef unless open( reportFile, ">$fileName" );

	tied(%{$CONFIG})->get_report_styles( 'report' );
  	my $rw = new wadg::HTMLWriter( -file => *reportFile,
  	                               -output => $$CONFIG{'report'}{Format}, 
  	                               -stylesheet => $$CONFIG{'report'}{_styles} );

	
	if( $temp_lines =~ /^(.+?)<!--\s*end general summary\s*-->(.+)$/s ) {
		$temp_lines = $2;
		$rw->write( $1 );
	} # end if

	# -- This may not be a good idea, but since we created 
	#    the writer object for our own use...
	$rw->{_qs_temp_lines} = $temp_lines;

	return $rw;
} # end openReportFile

# ----------------------------------------------------------
# Sub: wadg::rm::Report::closeReportFile [CLASS METHOD]
#
# Args: $handle
#		$handle	A handle to an HTMLWriter file for the object
#		$footer	An optional footer to put at the bottom of the file
#
# Description: Finishes writing data to a report file and 
# closes the file associated with $handle.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Jun19 Created method from quicksummary sub.         JW
# 2000Oct17 Changed qw_temp_lines to scalar.              JW
# ----------------------------------------------------------
sub closeReportFile {
	my( $rw ) = @_;
	$rw->write( $rw->{_qs_temp_lines} );
	return close $rw->{file};
} # end closeReportFile

##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################

# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
