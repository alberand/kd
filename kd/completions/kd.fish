# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
function __fish_kd_global_optspecs
	string join \n c/config= d/debug h/help V/version
end

function __fish_kd_needs_command
	# Figure out if the current invocation already has a command.
	set -l cmd (commandline -opc)
	set -e cmd[1]
	argparse -s (__fish_kd_global_optspecs) -- $cmd 2>/dev/null
	or return
	if set -q argv[1]
		# Also print the command, so this can be used to figure out what it is.
		echo $argv[1]
		return 1
	end
	return 0
end

function __fish_kd_using_subcommand
	set -l cmd (__fish_kd_needs_command)
	test -z "$cmd"
	and return 1
	contains -- $cmd[1] $argv
end

complete -c kd -n "__fish_kd_needs_command" -s c -l config -d 'Sets a custom config file' -r -F
complete -c kd -n "__fish_kd_needs_command" -s d -l debug -d 'Turn debugging information on'
complete -c kd -n "__fish_kd_needs_command" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_needs_command" -s V -l version -d 'Print version'
complete -c kd -n "__fish_kd_needs_command" -f -a "init" -d 'Initialize development environment'
complete -c kd -n "__fish_kd_needs_command" -f -a "build" -d 'Build image'
complete -c kd -n "__fish_kd_needs_command" -f -a "run" -d 'Run QEMU test system'
complete -c kd -n "__fish_kd_needs_command" -f -a "update" -d 'Update \'kd\' environment'
complete -c kd -n "__fish_kd_needs_command" -f -a "config" -d 'Generate minimal kernel config for VM'
complete -c kd -n "__fish_kd_needs_command" -f -a "debug" -d 'Developer tools'
complete -c kd -n "__fish_kd_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c kd -n "__fish_kd_using_subcommand init" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand build" -l name -d 'Name of a test config to use' -r
complete -c kd -n "__fish_kd_using_subcommand build" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand run" -l name -d 'Name of a test config to use' -r
complete -c kd -n "__fish_kd_using_subcommand run" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand update" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand config" -s o -l output -d 'Output filename' -r
complete -c kd -n "__fish_kd_using_subcommand config" -l name -d 'Name of a test config to use' -r
complete -c kd -n "__fish_kd_using_subcommand config" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand debug" -l name -d 'Name of a config to use' -r
complete -c kd -n "__fish_kd_using_subcommand debug" -s c -l config -d 'Output config'
complete -c kd -n "__fish_kd_using_subcommand debug" -s h -l help -d 'Print help'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "init" -d 'Initialize development environment'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "build" -d 'Build image'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "run" -d 'Run QEMU test system'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "update" -d 'Update \'kd\' environment'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "config" -d 'Generate minimal kernel config for VM'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "debug" -d 'Developer tools'
complete -c kd -n "__fish_kd_using_subcommand help; and not __fish_seen_subcommand_from init build run update config debug help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
