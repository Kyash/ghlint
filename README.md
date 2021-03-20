# githublint
Find problems in your GitHub settings.

## Usage

Displayed by executing the following command:

```sh
docker run --rm docker.pkg.github.com/kyash/githublint/githublint -h
```

### example

```
docker run --rm -e GITHUB_TOKEN docker.pkg.github.com/kyash/githublint/githublint orgs/Kyash
```

## Prerequisites

- Docker

## Development

### Getting Started

Launch the development environment

```sh
bash -i ./launch_dev_env.sh
```

### Dependencies

- GitHub REST API
- cURL v7.75.0+
- Bash v5.0+
- Node.js v10.24.0+
- jq v1.6+

### Further reading

- [Generating a new SSH key and adding it to the ssh-agent - GitHub Docs](https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Kyash/githublint
