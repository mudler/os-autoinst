package OpenQA::Test;
use Mojo::Base -base;

has [qw(lastscreenshot result wav_fn class category)];
has [qw(activated_consoles details)] => sub { [] };
has activated_consoles => sub { [] };
has [qw(running test_count screen_count post_fail_hook_running timeoutcounter dents)] => 0;
has parent_test => sub { [] };

1;
