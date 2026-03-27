
use builtin;
use str;

set edit:completion:arg-completer[kd] = {|@words|
    fn spaces {|n|
        builtin:repeat $n ' ' | str:join ''
    }
    fn cand {|text desc|
        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
    }
    var command = 'kd'
    for word $words[1..-1] {
        if (str:has-prefix $word '-') {
            break
        }
        set command = $command';'$word
    }
    var completions = [
        &'kd'= {
            cand -c 'Sets a custom config file'
            cand --config 'Sets a custom config file'
            cand -d 'Turn debugging information on'
            cand --debug 'Turn debugging information on'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
            cand init 'Initialize development environment'
            cand build 'Build image'
            cand run 'Run QEMU test system'
            cand update 'Update ''kd'' environment'
            cand config 'Generate minimal kernel config for VM'
            cand debug 'Developer tools'
            cand help 'Print this message or the help of the given subcommand(s)'
        }
        &'kd;init'= {
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;build'= {
            cand --name 'Name of a test config to use'
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;run'= {
            cand --name 'Name of a test config to use'
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;update'= {
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;config'= {
            cand -o 'Output filename'
            cand --output 'Output filename'
            cand --name 'Name of a test config to use'
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;debug'= {
            cand --name 'Name of a config to use'
            cand -c 'Output config'
            cand --config 'Output config'
            cand -h 'Print help'
            cand --help 'Print help'
        }
        &'kd;help'= {
            cand init 'Initialize development environment'
            cand build 'Build image'
            cand run 'Run QEMU test system'
            cand update 'Update ''kd'' environment'
            cand config 'Generate minimal kernel config for VM'
            cand debug 'Developer tools'
            cand help 'Print this message or the help of the given subcommand(s)'
        }
        &'kd;help;init'= {
        }
        &'kd;help;build'= {
        }
        &'kd;help;run'= {
        }
        &'kd;help;update'= {
        }
        &'kd;help;config'= {
        }
        &'kd;help;debug'= {
        }
        &'kd;help;help'= {
        }
    ]
    $completions[$command]
}
