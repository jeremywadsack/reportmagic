############################################################
#
# Module: wadg::rm::Report::RangeReport
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
# 2000.Apr.27 Changed to a general 'range' report for
#             Analog's SIZE and PROCTIME reports          JW
############################################################
package wadg::rm::Report::RangeReport;
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
# 1999Mar09 Uses standard parsing of available columns    JW
# 2000Apr25 Created method from old FileSizeReport sub    JW
# 09Jan2002 Changed charset conversion only on Latin-1    JW
# 14Aug2002 Removed <pre> formatting; didn't look good    JW
# ----------------------------------------------------------
sub _format_data_label {
	my $self = shift;
	my( $data ) = @_;
	my $dsep = $self->{_LANG}->val( 'Symbols', 'decimalSeparator' );

	#
	# First decode the point, in case it contains encoding.
	# Then encode the point in case it doesn't
	# Only do this if the character set it iso-8859-1 though, since 
	# HTML::Entities only supports that charcter set.
	# [Thanks to Jonas Smedegaard for the patch]
	my $charset = $self->{_LANG}->val( 'Language', 'CharacterSet' ) || '';
	if( $charset eq "iso-8859-1" ) {
		HTML::Entities::decode($data);
		HTML::Entities::encode($data);
	} # end if

	# Now convert number formats to localizations:
	$data =~ s/(\d)\.(\d)/$1$dsep$2/g;

	# The data for these reports are formatted to be on one line, so 
	# replace spaces with &nbsp;es and '-' with entities to avoid breaks
	#** Would work better if we could push a 'nobreak' cell attribute to the parent
	#   in fact, this would work nicely for the right-align kludge in number formatted
	#   cells with _format_data_item() too.
	$data =~ s/ /&#160;/g;
	$data =~ s/-/&#45;/g;
	#$data = $self->{writer}->pre( $data );
	
	return $data;
} # end _format_data_label


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
