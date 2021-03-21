# githublint
Find problems in your GitHub settings.

## Installation

```sh
git clone git@github.com:Kyash/githublint.git
cd githublint
install -m 755 ./bin/githublint /usr/local/bin
```

## Usage

Displayed by executing the following command:

```sh
githublint -h
```

### Example

```
githublint orgs/Kyash
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
