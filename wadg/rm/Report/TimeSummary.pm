############################################################
#
# Module: wadg::rm::Report::TimeSummary
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
# 2000.May.29 Added support for SummaryN in rdata.ini     JW
############################################################
package wadg::rm::Report::TimeSummary;
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

	# Define some object variables
	my $i = 1;
	while( defined $self->{_CONFIG}{$self->{token}}{"Summary$i"} ) {
 		my( $def, $lbl ) = $self->{_CONFIG}{$self->{token}}{"Summary$i"} =~ /\[([^\]]+)\]\s*,\s*(.*)\s*/;
 		$self->{_summaries}{"Summary$i"}{label} = $lbl;
		### Yeah, I know this is hard to maintain, but it should be faster than a bunch of subs
		### Suppose it could be done with a foreach loop and push.
		$self->{_summaries}{"Summary$i"}{definition} = [ map { /(\d+)-(\d+)/ ? map( sprintf("%02d", $_), eval "$1..$2") : /^\d+$/ ? sprintf("%02d", $_) : $_ } split( ',', $def ) ];
		$i++;
	} # end while
	$self->{_summary_count} = $i - 1;
	
	bless ($self, $class);
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
# Description: Process a report line by collecting the summary 
# data into our hashes and continuing with SUPER
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Mar08 Combined both time summaries to one routine. 
#           Special handling is provided by specific 
#           hash references and names and values defined 
#           in rdata.ini                                  JW
# 2000Apr25 Moved formatting to _format_XXXX_label        JW
# 12Dec2002 Added summary handling for English case       JW
# 21Feb2003 Added workaround for Hungarian analog files   JW
# 18Mar2003 English Daily Summary was processing twice    JW
# ----------------------------------------------------------
sub process {
	my $self = shift;
	my( $point, @myLine ) = $self->_format_data_columns( @_ );
	my( %tempHash );
	my $processed = 0;
	
	wadg::rm::CROParser::splitColumns( $self->{columns}, \%tempHash, @myLine );

	#
	# Workaround for Hungarian language files: 
	# In Analog's Hungarian language files anything less than four 
	# letters is padded with spaces
	#
	$point =~ s/\s+$//;


	# Process summaries
	my( $i, $c );
	for( $i = 1; $i <= $self->{_summary_count}; $i++ ) {
		if( grep {lc($point) eq lc($_)} @{$self->{_summaries}{"Summary$i"}{definition}} ) {
			foreach $c (split / */, $self->{columns}) {
		 		$self->{_summaries}{"Summary$i"}{$c} += $tempHash{$c};
				$processed ++;
			} # end foreach
		} # end if
	} # end for

	# In the case of the Daily Summary, we also want to support 
	# English shortnames if those were used and the language is 
	# not English
	## This is a hack. I don't like it. Should be done in config!
	unless( $processed ) {
		if( grep {lc($point) eq lc($_)} qw(mon tue wed thu fri) ) {
			foreach $c (split / */, $self->{columns}) {
				$self->{_summaries}{Summary1}{$c} += $tempHash{$c};
			} # end foreach
		} # end if
		if( grep {lc($point) eq lc($_)} qw(sat sun) ) {
			foreach $c (split / */, $self->{columns}) {
				$self->{_summaries}{Summary2}{$c} += $tempHash{$c};
			} # end foreach
		} # end if
	} # end unless
	
	return $self->SUPER::process( @_ );

} # end process

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
# 11Jun2001 Added support for new Analog 5 summaries      JW
# 19Jun2001 Fixed bug in date formatting and optimized    JW
# 06Feb2003 Fixed problem with German/English summaries   JW
# 21Feb2003 Added workaround for Hungarian analog files   JW
# ----------------------------------------------------------
sub _format_data_label {
	my $self = shift;
	my $point = shift;
	my @short_days = $self->{_LANG}->val( 'Dates', 'shortDays' );
	my @en_short_days = qw( Sun Mon Tue Wed Thu Fri Sat );

	#
	# Workaround for Hungarian language files: 
	# In Analog's Hungarian language files anything less than four 
	# letters is padded with spaces
	#
	$point =~ s/\s+$//;
	
	#
	# Try matching point to week day abreviations
	# We need to match a whole word here, but not the whole string.
	# Whole word so German 'Mo' doesn't only match part of English "Mon"
	# and not whole string because hour-of-the-week is like Mon/23
	#
	my $day;
	# First try locale
	my $i = 0;
	foreach $day (@short_days) {
		last if $point =~ s/\b$day\b/$i/;
		$i++;
	} # end foreach
	# Next try English, if we haven't found it
	if( $i == @short_days ) {
		$i = 0;
		foreach $day (@en_short_days) {
			last if $point =~ s/\b$day\b/$i/;
			$i++;
		} # end foreach
	} # end if

	# Push the dates deeper, if they need to be
	my $p = $self->{_CONFIG}{$self->{token}}{PushDates};
	if( defined $p && $p ) {
		my @d = split( /\D+/, $point );
		while( $p-- ) {
			unshift @d, '0';
		} # end while
		$point = $self->{_FORMATTER}->getDateString( @d ); #"$d[0]/$d[1]/$d[2] $d[3]:$d[4]";
	} # end if
	
	#  - Only format date-like strings
	if( $point =~ /\d/ ) {
		$point = $self->{_FORMATTER}->formatDate( $self->{_CONFIG}{$self->{token}}{TimeFormat}, $point );
	} # end unless

	return $point;
} # end _format_data_label


# ----------------------------------------------------------
# Sub: _format_graph_label
#
# Args: $data
#	$data	The data item label to be formatted
#
# Description: Formats the data label for the graphs.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# ----------------------------------------------------------
sub _format_graph_label {
	my $self = shift;
	return $self->_format_data_label( @_ );
} # end _format_graph_label


# ----------------------------------------------------------
# Sub: _write_summary
#
# Args: (None)
#
# Description: Writes out the summary information for time 
# summaries. This outputs those special summary rows.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Built from parts in endReport                 JW
# 08Mar2003 Skip empty summary rows (set to empty value)  JW
# ----------------------------------------------------------
sub _write_summary {
	my $self = shift;
	my @columns = split //, $self->{columns};
	
	my( $i, $c );
	for( $i = 1; $i <= $self->{_summary_count}; $i++ ) {
		my @tmpAry = ( $self->{_summaries}{"Summary$i"}{label} );
		next unless $tmpAry[0];		# Don't bother if there's no label
		foreach $c ( @columns ) {
			push( @tmpAry, $self->{_summaries}{"Summary$i"}{$c} );
		} # end foreach
		$self->__summary_row( \@columns, \@tmpAry );
	} # end for

	return $self->SUPER::_write_summary( @_ );
} # end _write_summary


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
