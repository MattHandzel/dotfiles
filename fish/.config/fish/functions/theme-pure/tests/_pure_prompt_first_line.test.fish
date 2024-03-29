source (status dirname)/fixtures/constants.fish
source (status dirname)/../functions/_pure_prompt_first_line.fish
@echo (_print_filename (status filename))


function before_all
    _purge_configs
    _disable_colors

    mkdir -p /tmp/test
    cd /tmp/test
    git init --quiet
    set SSH_CONNECTION 127.0.0.1 56422 127.0.0.1 22

    function _pure_print_prompt
        string join ' ' $argv
    end
    function _pure_prompt_ssh
        echo 'user@hostname'
    end
    function _pure_prompt_container
    end
    function _pure_prompt_k8s
    end
    function _pure_prompt_git
        echo master
    end
    function _pure_prompt_command_duration
        echo 1s
    end
    function _pure_string_width
        echo 15
    end
    function _pure_prompt_current_folder
        pwd
    end
end
before_all

function after_all
    functions --erase _pure_print_prompt
    functions --erase _pure_prompt_ssh
    functions --erase _pure_prompt_container
    functions --erase _pure_prompt_k8s
    functions --erase _pure_prompt_git
    functions --erase _pure_prompt_command_duration
    functions --erase _pure_string_width
    functions --erase _pure_prompt_current_folder
end


@test "_pure_prompt_first_line: print current directory, git, user@hostname (ssh-only), command duration" (
    set --universal pure_enable_git true
    set --universal pure_begin_prompt_with_current_directory true
    _pure_prompt_first_line

    rm -rf /tmp/test
) = '/tmp/test master user@hostname 1s'

@test "_pure_prompt_first_line: print user@hostname (ssh-only), current directory, git, command duration" (
    set --universal pure_enable_git true
    set --universal pure_begin_prompt_with_current_directory false
    _pure_prompt_first_line

    rm -rf /tmp/test
) = 'user@hostname /tmp/test master 1s'

if test "$USER" = nemo # avoid destroying other user's configuration
    @test "_pure_prompt_first_line: displays 'nemo@hostname' when inside container" (
    function _pure_prompt_container; echo $USER'@hostname'; end

    string match --quiet --entire --regex "nemo@[\w]+" (_pure_prompt_first_line)
) $status -eq $SUCCESS
end

@test "_pure_prompt_first_line: show kubernetes context and namespace" (
    function _pure_prompt_k8s; echo 'context/namespace'; end

    string match --quiet --entire --regex "context/namespace" (_pure_prompt_first_line)
) $status -eq $SUCCESS

after_all
