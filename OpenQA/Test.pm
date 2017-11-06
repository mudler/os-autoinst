package OpenQA::Test;
use Mojo::Base -base;
use basetest;
use Carp 'croak';

has [qw(lastscreenshot wav_fn class category)];
has [qw(activated_consoles details)] => sub { [] };
has activated_consoles => sub { [] };
has [qw(running test_count screen_count post_fail_hook_running timeoutcounter dents)] => 0;
has [qw(parent_test ocr_checklist)] => sub { [] };
has test_flags     => sub { {} };
has post_fail_hook => sub { 1 };

sub run           { }
sub pre_run_hook  { 1 }
sub post_run_hook { 1 }

sub new {
    my $self = shift->SUPER::new(@_);
    $self->{lastscreenshot}         = undef;
    $self->{details}                = [];
    $self->{result}                 = undef;
    $self->{running}                = 0;
    $self->{test_count}             = 0;
    $self->{screen_count}           = 0;
    $self->{wav_fn}                 = undef;
    $self->{dents}                  = 0;
    $self->{post_fail_hook_running} = 0;
    $self->{timeoutcounter}         = 0;
    $self->{activated_consoles}     = [];
    return $self;
}

*is_applicable               = \&basetest::is_applicable;
*_framenumber_to_timerange   = \&basetest::_framenumber_to_timerange;
*record_screenmatch          = \&basetest::record_screenmatch;
*_serialize_match            = \&basetest::_serialize_match;
*record_screenfail           = \&basetest::record_screenfail;
*remove_last_result          = \&basetest::remove_last_result;
*result                      = \&basetest::result;
*start                       = \&basetest::start;
*done                        = \&basetest::done;
*fail_if_running             = \&basetest::fail_if_running;
*skip_if_not_running         = \&basetest::skip_if_not_running;
*timeout_screenshot          = \&basetest::timeout_screenshot;
*run_post_fail               = \&basetest::run_post_fail;
*runtest                     = \&basetest::runtest;
*save_test_result            = \&basetest::save_test_result;
*next_resultname             = \&basetest::next_resultname;
*record_resultfile           = \&basetest::record_resultfile;
*record_serialresult         = \&basetest::record_serialresult;
*record_soft_failure_result  = \&basetest::record_soft_failure_result;
*register_extra_test_results = \&basetest::register_extra_test_results;
*record_testresult           = \&basetest::record_testresult;
*_result_add_screenshot      = \&basetest::_result_add_screenshot;
*take_screenshot             = \&basetest::take_screenshot;
*capture_filename            = \&basetest::capture_filename;
*stop_audiocapture           = \&basetest::stop_audiocapture;
*verify_sound_image          = \&basetest::verify_sound_image;
*standstill_detected         = \&basetest::standstill_detected;
*rollback_activated_consoles = \&basetest::rollback_activated_consoles;

1;
