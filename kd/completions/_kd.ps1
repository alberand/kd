
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'kd' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'kd'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
        }
        $element.Value
    }) -join ';'

    $completions = @(switch ($command) {
        'kd' {
            [CompletionResult]::new('-c', '-c', [CompletionResultType]::ParameterName, 'Sets a custom config file')
            [CompletionResult]::new('--config', '--config', [CompletionResultType]::ParameterName, 'Sets a custom config file')
            [CompletionResult]::new('-d', '-d', [CompletionResultType]::ParameterName, 'Turn debugging information on')
            [CompletionResult]::new('--debug', '--debug', [CompletionResultType]::ParameterName, 'Turn debugging information on')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('-V', '-V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('init', 'init', [CompletionResultType]::ParameterValue, 'Initialize development environment')
            [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, 'Build image')
            [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, 'Run QEMU test system')
            [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, 'Update ''kd'' environment')
            [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, 'Generate minimal kernel config for VM')
            [CompletionResult]::new('debug', 'debug', [CompletionResultType]::ParameterValue, 'Developer tools')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'kd;init' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;build' {
            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'Name of a test config to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;run' {
            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'Name of a test config to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;update' {
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;config' {
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'Output filename')
            [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, 'Output filename')
            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'Name of a test config to use')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;debug' {
            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'Name of a config to use')
            [CompletionResult]::new('-c', '-c', [CompletionResultType]::ParameterName, 'Output config')
            [CompletionResult]::new('--config', '--config', [CompletionResultType]::ParameterName, 'Output config')
            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
            break
        }
        'kd;help' {
            [CompletionResult]::new('init', 'init', [CompletionResultType]::ParameterValue, 'Initialize development environment')
            [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, 'Build image')
            [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, 'Run QEMU test system')
            [CompletionResult]::new('update', 'update', [CompletionResultType]::ParameterValue, 'Update ''kd'' environment')
            [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, 'Generate minimal kernel config for VM')
            [CompletionResult]::new('debug', 'debug', [CompletionResultType]::ParameterValue, 'Developer tools')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'kd;help;init' {
            break
        }
        'kd;help;build' {
            break
        }
        'kd;help;run' {
            break
        }
        'kd;help;update' {
            break
        }
        'kd;help;config' {
            break
        }
        'kd;help;debug' {
            break
        }
        'kd;help;help' {
            break
        }
    })

    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
        Sort-Object -Property ListItemText
}
