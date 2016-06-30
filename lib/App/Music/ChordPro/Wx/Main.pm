#! perl

use strict;
use warnings;

# Implementation of App::Music::ChordPro::Wx::Main_wxg details.

package App::Music::ChordPro::Wx::Main;

# App::Music::ChordPro::Wx::Main_wxg is generated by wxGlade and contains
# all UI associated code.

use base qw( App::Music::ChordPro::Wx::Main_wxg );

use Wx qw[:everything];
use Wx::Locale gettext => '_T';

use App::Music::ChordPro;
use File::Temp qw( tempfile );

our $VERSION = $App::Music::ChordPro::VERSION;

sub new {
    my $self = bless $_[0]->SUPER::new(), __PACKAGE__;

    $self;
}

# Explicit (re)initialisation of this class.
sub init {
    my ( $self ) = @_;

    my $font = Wx::Font->new( 12, wxFONTFAMILY_MODERN, wxFONTSTYLE_NORMAL,
			      wxFONTWEIGHT_NORMAL );
    $self->{t_source}->SetFont($font);
    Wx::Log::SetTimestamp(' ');
    if ( @ARGV && -s $ARGV[0] ) {
	$self->openfile( shift(@ARGV) );
	return 1;
    }

    $self->opendialog;
    $self->quit, return unless $self->{_currentfile};
    return 1;
}

################ Internal methods ################

sub opendialog {
    my ($self) = @_;
    my $fd = Wx::FileDialog->new
      ($self, _T("Choose ChordPro file"),
       "", "",
       "ChordPro files (*.cho,*.crd,*.chopro,*.chord,*.chordpro)|*.cho;*.crd;*.chopro;*.chord;*.chordpro|All files|*.*",
       0|wxFD_OPEN|wxFD_FILE_MUST_EXIST,
       wxDefaultPosition);
    my $ret = $fd->ShowModal;
    if ( $ret == wxID_OK ) {
	$self->openfile( $fd->GetPath );
    }
    $fd->Destroy;
}

sub quit {
    my ( $self ) = @_;
    $self->Destroy;
}

sub openfile {
    my ( $self, $file ) = @_;
    unless ( $self->{t_source}->LoadFile($file) ) {
	my $md = Wx::MessageDialog( $self,
				    "Error opening $file: $!",
				    "File open error",
				    wxOK | wxICON_ERROR );
	$md->ShowModal;
	$md->Destroy;
	return;
    }
    #### TODO: Get rid of selection on Windows
    $self->{_currentfile} = $file;
    if ( $self->{t_source}->GetValue =~ /^\{\s*title[: ]+([^\}]*)\}/m ) {
	my $n = $self->{t_source}->GetNumberOfLines;
	Wx::LogStatus("Loaded: $1 ($n line" .
		      ( $n == 1 ? "" : "s" ) .
		      ")");
	$self->{sz_source}->GetStaticBox->SetLabel($1);
    }
}

my ( $preview_cho, $preview_pdf );

sub preview {
    my ( $self ) = @_;

    # We can not unlink temps because we do not know when the viewer
    # is ready. So the best we can do is reuse the files.
    unless ( $preview_cho ) {
	( undef, $preview_cho ) = tempfile( OPEN => 0 );
	$preview_pdf = $preview_cho . ".pdf";
	$preview_cho .= ".cho";
	unlink( $preview_cho, $preview_pdf );
    }

    $self->{t_source}->SaveFile($preview_cho);

    #### ChordPro

    @ARGV = ();			# just to make sure
    $::__EMBEDDED__ = 1;
    my $options = App::Music::ChordPro::app_setup( "ChordPro", $VERSION );

    use App::Music::ChordPro::Output::PDF;
    $options->{output} = $preview_pdf;
    $options->{generate} = "PDF";
    $options->{backend} = "App::Music::ChordPro::Output::PDF";

    # Setup configuration.
    use App::Music::ChordPro::Config;
    $::config ||= App::Music::ChordPro::Config::configurator($options);

    # Parse the input.
    use App::Music::ChordPro::Songbook;
    my $s = App::Music::ChordPro::Songbook->new;

    my @msgs;
    $SIG{__WARN__} = sub {
	push( @msgs, join("", @_) );
	Wx::LogWarning($msgs[-1]);
    };

    $options->{diagformat} = 'Line %n, %m';
    $s->parsefile( $preview_cho, $options );

    if ( @msgs ) {
	Wx::LogStatus( @msgs . " message" .
		       ( @msgs == 1 ? "" : "s" ) . "." );
	Wx::LogError("Problems found!");
	return;
    }

    # Generate the songbook.
    my $res = App::Music::ChordPro::Output::PDF->generate_songbook( $s, $options );

    if ( -e $preview_pdf ) {
	Wx::LogStatus("Output generated, starting previewer");
	my $wxTheMimeTypesManager = Wx::MimeTypesManager->new;
	my $ft = $wxTheMimeTypesManager->GetFileTypeFromExtension("pdf");
	if ( $ft ) {
	    my $cmd = $ft->GetOpenCommand($preview_pdf);
	    Wx::ExecuteCommand($cmd);
	}
	else {
	    Wx::LaunchDefaultBrowser("file://" . $preview_pdf);
	}
    }
    unlink( $preview_cho );
}

sub saveas {
    my ( $self, $file ) = @_;
    $self->{t_source}->SaveFile($file);
    Wx::LogStatus( "Saved." );
}

################ Event handlers ################

# Event handlers override the subs generated by wxGlade in the _wxg class.

sub OnOpen {
    my ($self, $event) = @_;
    if ( $self->{t_source} && $self->{t_source}->IsModified ) {
	my $md = Wx::MessageDialog->new
	  ( $self,
	    "File " . $self->{_currentfile} . " has been changed.\n".
	    "Do you want to save your changes?",
	    "File has changed",
	    0 | wxCANCEL | wxYES_NO | wxYES_DEFAULT | wxICON_QUESTION );
	my $ret = $md->ShowModal;
	$md->Destroy;
	return if $ret == wxID_CANCEL;
	if ( $ret == wxID_YES ) {
	    $self->saveas( $self->{_currentfile} );
	}
    }
    $self->opendialog;
}

sub OnSaveAs {
    my ($self, $event) = @_;
    my $fd = Wx::FileDialog->new
      ($self, _T("Choose output file"),
       "", "",
       "*.txt",
       0|wxFD_SAVE|wxFD_OVERWRITE_PROMPT,
       wxDefaultPosition);
    my $ret = $fd->ShowModal;
    if ( $ret == wxID_OK ) {
	$self->export( $fd->GetPath );
    }
    $fd->Destroy;
}

sub OnSave {
    my ($self, $event) = @_;
    $self->saveas( $self->{_currentfile} );
}

sub OnPreview {
    my ( $self, $event ) = @_;
    $self->preview;
}

sub OnExit {
    my ( $self, $event ) = @_;
    if ( $self->{t_source} && $self->{t_source}->IsModified ) {
	my $md = Wx::MessageDialog->new
	  ( $self,
	    "File " . $self->{_currentfile} . " has been changed.\n".
	    "Do you want to save your changes?",
	    "File has changed",
	    0 | wxCANCEL | wxYES_NO | wxYES_DEFAULT | wxICON_QUESTION );
	my $ret = $md->ShowModal;
	$md->Destroy;
	return if $ret == wxID_CANCEL;
	if ( $ret == wxID_YES ) {
	    $self->saveas( $self->{_currentfile} );
	}
    }
    $self->quit;
}

sub OnUndo {
    my ($self, $event) = @_;
    $self->{t_source}->CanUndo
      ? $self->{t_source}->Undo
	: Wx::LogStatus("Sorry, can't undo yet");
}

sub OnRedo {
    my ($self, $event) = @_;
    $self->{t_source}->CanRedo
      ? $self->{t_source}->Redo
	: Wx::LogStatus("Sorry, can't redo yet");
}

sub OnCut {
    my ($self, $event) = @_;
    $self->{t_source}->Cut;
}

sub OnCopy {
    my ($self, $event) = @_;
    $self->{t_source}->Copy;
}


sub OnPaste {
    my ($self, $event) = @_;
    $self->{t_source}->Paste;
}

sub OnDelete {
    my ($self, $event) = @_;
    my ( $from, $to ) = $self->{t_source}->GetSelection;
    $self->{t_source}->Remove( $from, $to ) if $from < $to;
}

sub OnAbout {
    my ($self, $event) = @_;

    my $year = 1900 + (localtime(time))[5];

    # Sometimes version numbers are localized...
    my $dd = sub { my $v = $_[0]; $v =~ s/,/./g; $v };

    if ( rand > 0.5 ) {
	my $ai = Wx::AboutDialogInfo->new;
	$ai->SetName("ChordPro Preview Editor");
	$ai->SetVersion( $dd->($VERSION) );
	$ai->SetCopyright("Copyright $year Johan Vromans <jvromans\@squirrel.nl>");
	$ai->AddDeveloper("Johan Vromans");
	$ai->AddDeveloper("Perl version " . $dd->(sprintf("%vd",$^V)));
	$ai->AddDeveloper("wxWidgets version " . $dd->(Wx::wxVERSION));
	$ai->AddDeveloper(App::Packager::Packager() . " version " . $dd->($App::Packager::VERSION))
	  if $App::Packager::PACKAGED;
	$ai->AddDeveloper("GUI design with wxGlade");
	$ai->AddDeveloper("Some icons by www.flaticon.com");
	$ai->SetWebSite("http://www.chordpro.org");
	Wx::AboutBox($ai);
    }
    else {
	my $md = Wx::MessageDialog->new
	  ($self, "ChordPro Preview Editor version " . $dd->($VERSION) . "\n".
	   "Copyright $year Johan Vromans <jvromans\@squirrel.nl>\n".
	   "\n".
	   "GUI design with wxGlade, http://wxglade.sourceforge.net\n\n".
	   "Perl version " . $dd->(sprintf("%vd",$^V))."\n".
	   "wxPerl version " . $dd->($Wx::VERSION)."\n".
	   "wxWidgets version " . $dd->(Wx::wxVERSION)."\n".
	   ( $App::Packager::PACKAGED
	     ? App::Packager::Packager() . " version " . $dd->($App::Packager::VERSION)."\n"
	     : "" ),
	   "About ChordPro",
	   wxOK|wxICON_INFORMATION,
	   wxDefaultPosition);
	$md->ShowModal;
	$md->Destroy;
    }
}

################ End of Event handlers ################

1;
