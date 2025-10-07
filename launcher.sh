#!/usr/bin/env bash

# Exit immediately on errors
set -e

# --- Helper function for usage ---
usage() {
    echo "Usage: $0 {start|stop|get-leader|list} [subcommand]"
    echo ""
    echo "Commands:"
    echo "  start {consul-server|consul-agent}   Start a Consul service"
    echo "  stop  {consul-server|consul-agent}   Stop a Consul service"
    echo "  get-leader                          Display current Consul leader"
    echo "  list                                List all running Consul services"
    exit 1
}

# --- Argument validation ---
if [ $# -lt 1 ]; then
    usage
fi

COMMAND=$1
SUBCOMMAND=$2

# --- Main logic ---
case "$COMMAND" in
    start)
        case "$SUBCOMMAND" in
            consul-server)
                echo "Starting Consul server..."
                # Example command (replace with your actual service start logic)
                systemctl start consul-server
                ;;
            consul-agent)
                echo "Starting Consul agent..."
                systemctl start consul-agent
                ;;
            *)
                echo "Error: 'start' requires a subcommand (consul-server or consul-agent)"
                usage
                ;;
        esac
        ;;
    stop)
        case "$SUBCOMMAND" in
            consul-server)
                echo "Stopping Consul server..."
                systemctl stop consul-server
                ;;
            consul-agent)
                echo "Stopping Consul agent..."
                systemctl stop consul-agent
                ;;
            *)
                echo "Error: 'stop' requires a subcommand (consul-server or consul-agent)"
                usage
                ;;
        esac
        ;;
    get-leader)
        echo "Fetching Consul leader..."
        # Replace with your actual command:
        consul operator raft list-peers | grep leader || echo "No leader found"
        ;;
    list)
        echo "Listing Consul services..."
        systemctl list-units --type=service | grep consul || echo "No Consul services found"
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        usage
        ;;
esac
