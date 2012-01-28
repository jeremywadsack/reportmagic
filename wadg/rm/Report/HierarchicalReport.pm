############################################################
#
# Module: wadg::rm::Report::HierarchicalReport
#
# Created: 20.April.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
############################################################
package wadg::rm::Report::HierarchicalReport;
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
	$self->{_level} = 0;

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
# 2000Apr25 Just saves the level and calls SUPER          JW
# ----------------------------------------------------------
sub process {
	my $self = shift;
	my( $point, @myLine ) = $self->_format_data_columns( @_ );

	#
	# Get the level from the 'l' column
	#
	if( $self->{columns} =~ /l/ ) {
		$self->{_level} = $myLine[index( $self->{columns}, 'l' )]
	} # end if

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
# of this report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# 09Jan2002 Changed charset conversion only on latin-1    JW
# ----------------------------------------------------------
sub _format_data_label {
	my $self = shift;
	my( $data ) = @_;

	my $cropChar = $self->{_CONFIG}->{$self->{token}}{Truncate} || '';
	my $elip = $self->{_LANG}->val( 'Symbols', 'ellipsis' );
	my $level = $self->{_level};

	# -- Crop long lines, if requested
	my $cropLineData = $data;
	if( ( $cropChar ne '' )  && ( length($data) > $cropChar ) ) {
		$cropLineData = substr( $data, 0, $cropChar ) . $elip;
	} # end if

	#
	# First decode the point, in case it contains encoding.
	# Then encode the point in case it doesn't
	# Only do this if the character set it iso-8859-1 though, since 
	# HTML::Entities only supports that charcter set.
	# [Thanks to Jonas Smedegaard for the patch]
	my $charset = $self->{_LANG}->val( 'Language', 'CharacterSet' ) || '';
	if( $charset eq "iso-8859-1" ) {
		HTML::Entities::decode($cropLineData);
		HTML::Entities::encode($cropLineData);
		# - Do this too. Even though it looks weird, it's the 'proper' way to 
		#   write CGI links in HTML (SEE RFC 1866)
		HTML::Entities::decode($data);
		HTML::Entities::encode($data);
	} # end if

	# -- Bold level 1 items
	if( $level == 1 ) {
		$cropLineData = $self->{writer}->b( $cropLineData );
	} # end if

	if( defined $self->{_CONFIG}{$self->{token}}{SmallFont} ) {
		$cropLineData = $self->{writer}->span( {class => 'smallfont'}, $cropLineData );
	} # end if

	# - Include links
	$cropLineData = $self->__format_data__include_links( $data, $cropLineData );

	# -- Indent item according to level
	while( --$level > 0 ) {
		$cropLineData = '&nbsp;&nbsp;&nbsp;' . $cropLineData;
	} # end while
	
	return $cropLineData;
} # end _format_data_label

# ----------------------------------------------------------
# Sub: _format_data_item
#
# Args: $data
#	$data	The data item to be formatted
#
# Description: Formats the data item by applying bold to 
# level 1 data
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr25 Created method                                JW
# 14Aug2002 Added call to SUPER for formatting            JW
# ----------------------------------------------------------
sub _format_data_item {
	my $self = shift;

	# Get formatted item first
	my $data = $self->SUPER::_format_data_item( @_ );
	
	# -- Bold level 1 items
	$data = $self->{writer}->b( $data ) if $self->{_level} == 1;

	return $data;
} # end _format_data_item

# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
