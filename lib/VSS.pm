package VSS;
$VERSION = '1.0.1';

# --------------------------------------------------------------
#  This is my first module ever, so if it
#  sucks then blame that.
#
#  This module is free software; you can redistribute it and/or
#  modify it under the same terms as Perl itself.
# --------------------------------------------------------------

use strict;
require Exporter;
require Win32::OLE;
require Carp;

our @ISA = qw(Exporter);

sub new {
	my $invocant = shift();
	my $class = ref($invocant) || $invocant;
	$class = bless {
		db_path => 'L:\FMCSA Projects\srcsafe.ini',
		username => 'BPrudent',
		password => 'BPrudent',
		vss_base => '$/Development/',
		debug => 0,

		_vssdb => undef
	}, $class;
	$class->init(@_);
	return $class;
}

sub init {
	my $self = shift();
	my %args = @_;

	foreach (keys %args) {
		if (exists $self->{$_}) {
			$self->{$_} = $args{$_};
		}
		else {
			Carp::croak ("unrecognized vss option $_");
		}
	}

	$self->{'_vssdb'} = Win32::OLE->new('SourceSafe');
	$self->oleerr();

	$self->{'_vssdb'}->Open($self->{'db_path'}, $self->{'username'}, $self->{'password'});
	$self->oleerr();
}

sub _itemize {
	my ($self, $item) = @_;

	if (!(UNIVERSAL::isa($item, 'Win32::OLE'))) {
		if ($item !~ m/^\$/) {
			$item = $self->{'vss_base'}.$item;
		}

		$item = $self->{'_vssdb'}->VSSItem($item);
		$self->oleerr();
		return ($item);
	}

	if (!(UNIVERSAL::isa($item, 'Win32::OLE'))) {
		return undef;
	}

	return ($item);
}

sub _itemize_name {
	my ($self, $item) = @_;

	if (UNIVERSAL::isa($item, 'Win32::OLE')) {
		return ($item->Spec());
	}

	if ($item !~ m/^\$/) {
		$item = $self->{'vss_base'}.$item;
	}

	return ($item);
}

sub _debug {
	my ($self, $val, $name) = @_;
	return if (!$self->{'debug'});
	if (UNIVERSAL::isa($val, 'Win32::OLE')) {
		print "debug $name is a VSS::Item or similar\n";
	}
	else {
		print "debug: $name is $val\n";
	}
}

sub item_exists {
	my ($self, $named_item) = @_;
	$named_item = $self->_itemize_name($named_item);
	my $err;

	$named_item = $self->{'_vssdb'}->VSSItem($named_item);
	$err = Win32::OLE->LastError();
	if ($err =~ m/0x8004d68f/ && $err =~ m/File or project not found/) {
		return 0;
	}

	return $named_item;
}

sub checkin {
	my ($self, $vss_item, $comment) = @_;
	$vss_item = $self->_itemize($vss_item);

	if (!$vss_item) { Carp::croak ("{VSS::checkin} don't know what $vss_item is"); }

	$vss_item->Checkin($comment);
	$self->oleerr();
	return ($vss_item);
}

sub checkout {
	my ($self, $vss_item, $comment) = @_;
	$vss_item = $self->_itemize($vss_item);

	if (!$vss_item) { Carp::croak ("{VSS::checkout} don't know what $vss_item is"); }

	if ($vss_item->IsCheckedOut()) { return undef; }

	$vss_item->Checkout($comment);
	$self->oleerr();
	return ($vss_item);
}

# does this work?
sub local_file {
	my ($self, $vss_item) = @_;
	$vss_item = $self->_itemize($vss_item);

	if (!$vss_item) { Carp::croak ("{VSS::local_file} don't know what $vss_item is"); }

	return ($vss_item->LocalSpec());
}

# no news is good news
sub share_and_branch {
	my ($self, $from, $to, $autocheckin) = @_;
	my $from = $self->_itemize($from);
	my $to = $self->_itemize($to);

	if (!$from) { Carp::croak ("{VSS::share_and_branch} don't know what $from is"); }
	if (!$to) { Carp::croak ("{VSS::share_and_branch} don't know what $to is"); }

	if ($from->IsCheckedOut()) {
		if ($autocheckin) {
			$self->checkin($from);
		}
		else {
			return(Win32::OLE->LastError());
		}
	}

	$self->share($from, $to, 1); # delete if exists
	$self->branch($to);

	return 0;
}

sub branch {
	my ($self, $file_item) = @_;
	$file_item = $self->_itemize($file_item);
	if (!$file_item->isa('Win32::OLE')) {
		Carp::croak("{VSS::branch} $file_item is not a valid VSSItem!!");
	}

	$file_item->Branch(); $self->oleerr();
}

sub share {
	my ($self, $from, $to, $delete_if_exists) = @_;
	$from = $self->_itemize($from);
	$to = $self->_itemize_name($to);

	if (!$from->isa('Win32::OLE')) {
		Carp::croak("{VSS::share} $from is not a valid VSSItem!!");
	}

	if ($self->item_exists($to)) {
		if ($delete_if_exists) {
			$self->destroy($to);
		}
		else {
			return "$to exists";
		}
	}

 	# get the parent directory name
	$to =~ s|^(.+)/(?:.*?)?$|$1/|;

	$to = $self->_itemize($to);

	if (!$to->isa('Win32::OLE')) {
		Carp::croak("{VSS::share} $to is not a valid VSSItem!!");
	}

	$to->Share($from); $self->oleerr();
	return 0;
}

sub destroy {
	my ($self, $item) = @_;
	$item = $self->_itemize($item);

	if (!$item->isa('Win32::OLE')) { Carp::croak ("Cannot destory $item!"); }

	$item->Destroy();
	$self->oleerr();
}

sub add {
	my ($self, $vss_dir, $local_file) = @_;
	$vss_dir = $self->_itemize_name($vss_dir);

	$vss_dir = $self->add_directories($vss_dir)->Add($local_file);
	$self->oleerr();
	return ($vss_dir); #it's actually an item.
}

sub add_directories { # ... unless they exist
	my ($self, $dir_path) = @_;
	my @all_dirs = split('/', $dir_path);
	my $dir_base = splice (@all_dirs, 0, 1).'/'; # should be $/
  	my $tmp_dir = $dir_base;
  	foreach my $dir (@all_dirs) {
		$tmp_dir .= "$dir/";
		if (!$self->item_exists($tmp_dir)) {
			$self->_itemize($dir_base)->NewSubProject($tmp_dir);
			$self->oleerr();
		}
		$dir_base = $tmp_dir;
	}

	return ($self->_itemize($dir_base));
}

sub oleerr {
	my $cache;
	if ($cache = Win32::OLE->LastError()) { Carp::croak("$cache\n"); }
}

1;

__END__

=head1 NAME

VSS - Visual Source Safe Class

=head1 SYNOPSIS

	use VSS;

	my $vss = VSS->new(db_path => 'L:/',
	            username => 'foo',
	            password => 'bar',
	            vss_base => '$/Development/');

	my $item = $vss->checkout('src/main.c');
	$item = $vss->checkin($item);

	$vss->share_and_branch('fmcsa/cmvdbc.htm.xml', '$/Production/fmcsa/cmvdbc.htm.xml');

=head1 WARNING

PLEASE DO NOT USE MICROSOFT VISUAL SOURCE SAFE UNLESS YOU HAVE TO!!
It is horrible software and pcvs or cvs or anything else is recommended.
If you are so unlucky as to have to use this all you need to know is what's
outlined below. You might also want to check out
L<http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dnvss/html/msdn_vssole.asp>

=head1 ARGUMENTS

The following arguments can be passed to this module:

=head2 db_path

The path to your srcsafe.ini file. In some versions of VSS you may need to pass the
name of the directory that contains the srcsafe.ini file. The default is what works
on my computer.

=head2 username

The username you use to log into VSS. The default is what works
on my computer.

=head2 password

The password you use to log into VSS. The default is my username.

=head2 vss_base

This is an optional, but recommended parameter. The function of such is for the _itemize and
_itemize_name functions allowing you to say things like 'project/file.c' instead of
'$/Development/project/file.c'. In that case you would set vss_base to '$Development/'.
Simple, huh? ;)

=head2 debug

Set to 1 to debug.

=head1 METHODS

Before we begin I should tell you that all parameters that are supposed to be a VSS item will
do its best to become a VSS item. What I mean is that every time you pass an argument that
requires an item or item name, it will be run through one of the functions _itemize or _itemize_name.
These are meant to be called only from the module, but I feel free to use them in your scripts
(though I won't document it here, for simplicity's sake). The functions do thier best to turn
a [full|partial] textual description into a VSS item or VSS item name.

=head2 item_exists

Pretty self-explanatory. If the function can obtain an item from the item name passed, it returns
1 otherwise 0.

=head2 checkin

Arguments:

=over

=item 1

VSS item or [full|partial] item name [required]

=item 2

Comment [optional]

=back

Returns: VSS Item

=head2 checkout

Arguments:

=over

=item 1

VSS item or [full|partial] item name [required]

=item 2

Comment [optional]

=back

Returns: VSS Item

=head2 local_file

Arguments:

=over

=item 1

VSS item or [full|partial] item name [required]

=back

Returns: Local file name

I'm not sure this function works X(.

=head2 share_and_branch

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the FROM item [required]

=item 2

VSS item or [full|partial] item name representing the TO item [required]

=item 3

AutoCheckIn 1 or 0. Determines if the function should checkin checked-out files. [optional] [default:0]

=back

Returns: 0 upon success; error string upon failure.

=head2 branch

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the file or project that was shared into. [required]

=back

Returns: nothing

=head2 share

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the FROM item [required]

=item 2

VSS item or [full|partial] item name representing the TO item [required]

=item 3

DeleteIfExists 1 or 0. Determines if the function should delete existing TO items. [optional] [default:0]

=back

Returns: 0 upon success; error string upon failure.

=head2 destroy

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the item to be destroyed [required]

=back

Returns: nothing

=head2 add

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the directory to add into. [required]

=item 2

Local file (full path, windows convention - use backslashes) to add. [required]

=back

If the director(y|ies) you're adding to don't exists, don't worry. This will call add_directories
to add them into VSS.

=head2 add_directories

Arguments:

=over

=item 1

VSS item or [full|partial] item name representing the director(y|ies) to create. [required]

=back

This function will create all the directories named, or none if they already exist.

=head1 BUGS

Plenty, but they're all within MS VSS itself so they'll never get resolved :).
If you do find a bug, let me know.

=head1 SEE ALSO

L<WIN32::OLE>
L<http://msdn.microsoft.com/library/en-us/dnvss/html/vssauto.asp>
L<http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dnvss/html/msdn_vssole.asp>

=head1 AUTHOR

BPrudent (Brandon Prudent)

email: xlacklusterx@hotmail.com
