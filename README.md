# ReqAzStore

A minimal plugin for Req to simplify interacting with Azure Storage accounts.  The plugin handles signing 
requests and adding common headers.

## Installation

Add to the list of your dependencies:

```elixir
def deps do
  [
    {:req_az_store, "~> 0.1.0"}
  ]
end
```

## Usage

You can use the ReqAzStore.attach() function to add the needed steps to your Req request pipeline:

```elixir
Req.new(base_url: "https://your_account_name.blob.core.windows.net")
|> ReqAzStore.attach()
```

There are two required options that must be set before sending your request:
* :account_name - the name of your storage account.
* :account_key - your storage account key to be used to sign requests.

```elixir
Req.new(base_url: "https://your_account_name.blob.core.windows.net")
|> ReqAzStore.attach()
|> Req.get!(account_name: "your_account_name", account_key: "really_long_key_from_account_settings")
```



