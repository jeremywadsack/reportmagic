############################################################
#
# Module: wadg::rm::Report::GeneralSummary
#
# Created: 20.March.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
############################################################
package wadg::rm::Report::GeneralSummary;
use strict;

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw( wadg::rm::Report );
} # end BEGIN
# non-exported package globals go here
use vars      qw();


############################
## The object constructor ##
############################
sub new {
	my $self = {};
	my $proto = shift;
	my %parms = @_;
	my $class = ref($proto) || $proto;

	bless ($self, $class);
	$self->{_units} = {};
	$self->{_unit} = {};
	$self->_initialize( %parms ) or return;
	
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
# Description: Processes a report line for the report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 05Dec2002 Changed byte encoding to be done on data item JW
# 04Feb2003 Patched up warnings for columns w/o Format    JW
# ----------------------------------------------------------
sub process {
	my $self = shift;
	my( $reportType ) = $self->{token};
	my $columns = $self->{columns};
	
	# -- Only process rows that are requested
	if( !defined $self->{_CONFIG}{$self->{token}}{Rows} || ($self->{_CONFIG}{$self->{token}}{Rows} eq '') || ($self->{_CONFIG}{$self->{token}}{Rows} =~ /\b$columns\b/gi) ) {
		my( $point ) = @_;

		# - More than one field is a date type
		if( @_ > 1 ) {
			$point = $self->{_FORMATTER}->getDateString( @_ );
			$point = $self->{_FORMATTER}->formatDate( $self->{_CDATA}->val( $columns, 'TimeFormat' ), $point );
		} # end if
		
		# - If it looks like a URL, then link it
		if( $point =~ m!^\w+://[\w\d\.\-]+(/|$)! ) {
			$point = $self->{writer}->a( {href => $point, target => '_top'}, $point );
		} # end if

		# If it has units and it's not bytes (cruft) then add those
		if( defined($self->{_CDATA}->val( $columns, 'Units' )) ) {
			if( !defined($self->{_CDATA}->val( $columns, 'Format' )) ||
			        ($self->{_CDATA}->val( $columns, 'Format' ) ne 'bytes') ) {
				 # Add units to other fields
				 $self->{_units}{$columns} = $self->{_CDATA}->val( $columns, 'Units' );
				 $self->{_unit}{$columns} = $self->{_CDATA}->val( $columns, 'Unit' );
			} # end unless
		} # end if

		# Swap shaded rows
		$self->{_shaded_row} = 1 - $self->{_shaded_row};
	
		# Output the table row
		$self->_data_row( $self->{_CDATA}->val( $columns, 'LongName' ), $point );
	} # end if

} # end process

# ----------------------------------------------------------
# Sub: start_table
#
# Args: (None)
#
# Description: Draws the table headers for the General Summary
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May06 Derived from wadg::rm::Report                 JW
# ----------------------------------------------------------
sub start_table {
	my $self = shift;
	my @columns = split(/ */, $self->{columns});
	my $altString = '';
	
	# - Create some summary text for the table
	#   Remove any HTML tags, though
	$altString = $self->{_CONFIG}{$self->{token}}{Description};
	$altString =~ s/<.+?>//g;
	my $tableBorder = '1';
	
	$self->{writer}->write( 
		$self->{writer}->br(),
		$self->{writer}->start_div( {align => 'CENTER'} ),
		$self->{writer}->start_table( {cellpadding => 5, cellspacing => 0, border => $tableBorder, width => '85%', summary => $altString } ),
		$self->{writer}->tr( 
			$self->{writer}->th( {colspan => 3, scope => 'COL'}, $self->{_CONFIG}{$self->{token}}{DataName} )
		),
	);
	
	return 0;
} # end start_table



# ----------------------------------------------------------
# Sub: end_report
#
# Args: (None)
#
# Description: Calls SUPER to finish the report page, then
# inserts the marker for the quick summary.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May06 Moved GeneralSummary stuff to its own class   JW
# ----------------------------------------------------------
sub end_report {
	my $self = shift;

	return if $self->{token} eq '';
	
	# Do the normal stuff
	$self->SUPER::end_report( @_ );

	# Add insertion point for QuickSummary _after_ nav table
	$self->{writer}->write( $self->{writer}->comment( 'end general summary' ) );

} # end end_report

##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: _format_data_item
#
# Args: $data
#	$data	The data item to be formatted
#
# Description: Adds units to items after they've been localized
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May03 If this column has units then add them        JW
# ----------------------------------------------------------
sub _format_data_item {
	my $self = shift;
	my( $data ) = $self->SUPER::_format_data_item(@_);
	
	
	if( ($data eq '1') && (defined $self->{_unit}{$self->{columns}}) ) {
		$data .= ' ' . $self->{_unit}{$self->{columns}};
	} elsif( defined $self->{_units}{$self->{columns}} ) {
		$data .= ' ' . $self->{_units}{$self->{columns}};
	} # end if

	return $data;
} # end _format_data_item


# ----------------------------------------------------------
# Sub: _data_row
#
# Args: @data
#	@data	The data to put in the row.
#
# Description: Writes out the data in the row of the table
# for a report. Calls the appropriate formatting methods for
# table and graph labels and data.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Subclassed to handle GeneralSummary columns   JW
# ----------------------------------------------------------
sub _data_row {
	my $self = shift;
	my( @data ) = @_;
	
	my @columns = ($self->{columns});
	$self->__table_row( $self->{_shaded_row}, \@columns, \@data );

} # end _data_row

# ----------------------------------------------------------
# Sub: __table_row
#
# Args: $row_color, $colref, $dataref
#	$row_color	The color (if any) to use for the row
#	$colref  	Reference to the list of column specs
#	$dataref 	Reference to the list of data to write to the row
#
# Description: Outputs data items into a table row.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Created from sources in _data_row             JW
# ----------------------------------------------------------
sub __table_row {
	my $self = shift;
	my( $row_color, $colref, $dataref ) = @_;
	my( @columns ) = @{$colref};
	my( @data ) = @{$dataref};
	
	$row_color = 'alt' . ($row_color + 1);

	$self->{writer}->write( $self->{writer}->start_tr() );

	# Get index number for line
	# --- Need this, even in GS, cause it counts our lines
	my $num = @{$self->{_chart}} + 1;

	# Print line index, if there is one
	if( $num eq '' ) {
		$self->{writer}->write( $self->{writer}->td( {class => $row_color}, '&nbsp;' ) );
	} else {
		$self->{writer}->write( $self->{writer}->td( {class => $row_color}, "$num." ) );
	} # end if

	#
	# Now, iterate through data set and output rows.
	#
	my $i = 0;
	foreach (@data) {
		my $c = 	$columns[0];

		# Skip undefined data
		next unless defined;
		if( ($i > 0) && ($self->{_CDATA}->val( $c, 'LongName' ) eq '') ) {
			$i++;
			next;
		} # end if

		#
		# Print line data
		#
		my %td = (class => $row_color, align => 'left');

		# If the data looks like a number then format right align.
		# Don't format IP numbers though and don't right-align anything in column 0
		if( ($i > 0) && (/^[\d\.]+$/) && !(/\d+\.\d+\./) ) {
			$td{align} = 'right';
			#$_ =  $self->{_FORMATTER}->formatNumber( $self->{_CDATA}->val( $c, 'NumberFormat' ), $_ );
		} # end if
		
		# - If no value insert a &nbsp;, otherwise format appropriately
		if( $_ eq '' ) {
			$_ = '&nbsp;';
		} elsif( $i == 0 ) {
			$_ = $self->_format_data_label( $_, $c );
		} else {
			$_ = $self->_format_data_item( $_, $c );
		} # end if 

		$self->{writer}->write( $self->{writer}->td( \%td, $_ ) );
		$i++;
	} # end foreach

	push @{$self->{_chart}}, $num;
	
	$self->{writer}->write( $self->{writer}->end_tr() );

} # end __table_row

# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
