############################################################
#
# Module: wadg::rm::Report::TimeReport
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
package wadg::rm::Report::TimeReport;
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
	$self->_initialize( %parms ) or return;

	return $self;
} # end new

##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: end_table
#
# Args: (None)
#
# Description: Reverses the data for the graphs if requested, 
# Then calls SUPER to closes the table for data columns.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May06 Created to put reverse code in proper place   JW
# ----------------------------------------------------------
sub end_table {
	my $self = shift;

	# If requested, invert datasets in @chart
	if( defined $self->{_CONFIG}{reports}{Reverse_Time} && $self->{_CONFIG}{reports}{Reverse_Time} != 0 ) {
		@{$self->{_chart}} = reverse @{$self->{_chart}};
	} # end if

	$self->SUPER::end_table(@_);
} # end end_table


##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################

# ----------------------------------------------------------
# Sub: _format_data_label
#
# Args: $data
#	$data	The data item label to be formatted
#
# Description: Formats the data label according to the style 
# set in the TimeFormat for the report
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# ----------------------------------------------------------
sub _format_data_label {
	my $self = shift;

	return $self->{_FORMATTER}->formatDate( $self->{_CONFIG}{$self->{token}}{TimeFormat}, @_ );

} # end _format_data_label

# ----------------------------------------------------------
# Sub: _format_graph_label
#
# Args: $data
#	$data	The data item label to be formatted
#
# Description: Formats the data label according to the style 
# set in the TimeFormat for the report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# ----------------------------------------------------------
sub _format_graph_label {
	my $self = shift;
	return $self->_format_data_label( @_ );
} # end _format_graph_label

# -----------------------------------------------------------------------------
# Sub: _write_summary
#
# Args: (None)
#
# Description: Writes out the summary information for time report. This 
# includes the "most active" time statements.
# -----------------------------------------------------------------------------
# Date      Modification                                                 Author
# -----------------------------------------------------------------------------
# 2000Apr25 Built from parts in endReport                                    JW
# 08Jan2002 Fixed bug where byte averages were off by a factor of 10         JW
# 26Nov2002 Added support for Show_Bytes_As setting                          JW
# -----------------------------------------------------------------------------
sub _write_summary {
	my $self = shift;
	my( $dType )     = split /[\012\015]+/, $self->{_CONFIG}{$self->{token}}{ShortName};
	my $formatSpec   = $self->{_CONFIG}{$self->{token}}{TimeFormat};
	my $dateStr      = $self->{_summaries}{$dType}{max}{name};

	# Close the table
	$self->end_table();

	# Output some summary text
	$self->{writer}->write( $self->{writer}->start_p( {-class => 'smallfont'} ) );

	# Maximum value label
	# *** Is this internationalized???
	$self->{writer}->write( $self->{_CONFIG}{$self->{token}}{MostActive} . " $dateStr : "  );

	# Maximum values list
	my $active_col = substr($self->{_CONFIG}{reports}{Active_Column}, 0, 1);
	my $c; # Because formatMessage or formatNumber destroys $_.
	foreach $c ( keys %{$self->{_summaries}{$dType}{max}} ) {
		next if $c eq 'name';
		$c .= '_' if $c eq uc($c);
		next if not defined $self->{_CDATA}->val( $c, 'Activity' );
		my $text = $self->{_FORMATTER}->formatMessage( 
			$self->{_CDATA}->val( $c, 'Activity' ), 
			$self->{_FORMATTER}->formatNumber( 
				$self->{_CDATA}->val( $c, 'NumberFormat' ), 
				$self->{_summaries}{$dType}{max}{substr($c, 0, 1)}
			)
		);
		if( substr($c, 0, 1) eq $active_col ) {
			$text = $self->{writer}->b( $text );
		} # end if
		$self->{writer}->write( "$text " );
	} # end foreach

	$self->{writer}->write( $self->{writer}->end_p() );
	$self->{writer}->write( $self->{writer}->start_p( {-class => 'smallfont'} ) );

	# Average results
	if( (defined $self->{_CONFIG}{$self->{token}}{Average}) && ($self->{_summaries}{$dType}{count}) ) {
		$self->{writer}->write( $self->{_CONFIG}{$self->{token}}{Average} . ': ' );
		foreach $c ( keys %{$self->{_summaries}{$dType}{total}} ) {
			$c .= '_' if $c eq uc($c);
			next if not defined $self->{_CDATA}->val( $c, 'Activity' );
			my $avg = int($self->{_summaries}{$dType}{total}{substr($c, 0, 1)} / ($self->{_summaries}{$dType}{count}));
			if( defined $self->{_CDATA}->val($c,'NumberFormat') ) {
				$avg = $self->{_FORMATTER}->formatNumber( $self->{_CDATA}->val($c,'NumberFormat'), $avg )
			} elsif( defined $self->{_CDATA}->val($c,'Format') ) {
				my $b = $self->{_CONFIG}{$self->{token}}{Show_Bytes_As};
				my $f = $self->{_CDATA}->val($c,'Format');
				if( defined($f) and ($f eq 'bytes') and defined($b) and $b ) {
					$avg = $self->{_FORMATTER}->format_value( $f, $avg, $b )
				} else {
					$avg = $self->{_FORMATTER}->format_value( $f, $avg )
				} # end if
			} # end if
			my $text = $self->{_FORMATTER}->formatMessage( $self->{_CDATA}->val( $c, 'Activity' ), $avg	);
			if( substr($c, 0, 1) eq $active_col ) {
				$text = $self->{writer}->b( $text );
			} # end if
			$self->{writer}->write( "$text " );
		} # end foreach
	} # end if
	

	$self->{writer}->write( $self->{writer}->end_p(), $self->{writer}->br(), $self->{writer}->hr() );

} # end _write_summary

# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
