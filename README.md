# hocker

Hocker is a Docker-like container runtime written in Crystal

## Commands 

```bash
create    Create a new container from an image
start     Start a container
exec      Run a command inside a running container
stop      Stop a running container
rm        Remove a stopped container
ps        List all containers
version   Show hocker version
help      Show this help message
```

## Examples

```bash
# 1. Create a new container named "web" using alpine image with interactive shell
hocker create --name web

# 2. Start it 
hocker start web    # Start in foreground. 'exit' to stop.
hocker start -d web                # -d = run in background

# 4. Run commands in a running container
hocker exec web hostname
hocker exec web ps aux

# 5. Get an interactive shell in a running container
hocker exec -i -t web /bin/sh      # -i = interactive, -t = TTY

# 6. Stop a running container
hocker stop web 
hocker stop -t 5 web               # wait up to 5 seconds before force kill

# 7. List containers
hocker ps

# 8. Remove a stopped container
hocker rm web
```
