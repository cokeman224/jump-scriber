defmodule Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 for Salesforce.

  Add `client_id`, `client_secret`, and optionally `redirect_uri` to your configuration.
  For sandbox use `site: "https://test.salesforce.com"`.
  """

  use OAuth2.Strategy

  require Logger

  @default_production [
    strategy: __MODULE__,
    site: "https://login.salesforce.com",
    authorize_url: "https://login.salesforce.com/services/oauth2/authorize",
    token_url: "https://login.salesforce.com/services/oauth2/token"
  ]

  @default_sandbox [
    strategy: __MODULE__,
    site: "https://test.salesforce.com",
    authorize_url: "https://test.salesforce.com/services/oauth2/authorize",
    token_url: "https://test.salesforce.com/services/oauth2/token"
  ]

  @doc """
  Construct a client for requests to Salesforce.

  Uses SALESFORCE_BASE_URL env to choose production vs sandbox.
  Default is production (login.salesforce.com).
  """
  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])
    base_url = config[:site] || System.get_env("SALESFORCE_BASE_URL") || "https://login.salesforce.com"

    defaults =
      if String.contains?(to_string(base_url), "test.salesforce.com") do
        @default_sandbox
      else
        @default_production
      end

    opts =
      defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)
      |> Keyword.put(:authorize_url, base_url <> "/services/oauth2/authorize")
      |> Keyword.put(:token_url, base_url <> "/services/oauth2/token")
      |> Keyword.put(:site, base_url)

      # Confirm credentials are present when building client (do not log secret value)
    secret = opts[:client_secret]
    Logger.debug(
      "[Salesforce OAuth] token client: client_id present=#{inspect(opts[:client_id] != nil and opts[:client_id] != "")}, " <>
      "client_secret present=#{inspect(secret != nil and secret != "")}, " <>
      "client_secret length=#{inspect(if is_binary(secret), do: byte_size(secret), else: 0)}"
    )
    json_library = Ueberauth.json_library()

    OAuth2.Client.new(opts)
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  @doc """
  Fetches an access token from the Salesforce token endpoint.
  Response includes instance_url, access_token, refresh_token, expires_in.
  """
  def get_access_token(params \\ [], opts \\ []) do
    case opts |> client() |> OAuth2.Client.get_token(params) do
      {:ok, %OAuth2.Client{token: %OAuth2.AccessToken{} = token}} ->
        {:ok, token}

      {:ok, %OAuth2.Client{token: nil}} ->
        {:error, {"no_token", "No token returned from Salesforce"}}

      {:error, %OAuth2.Response{body: %{"error" => error, "error_description" => description}}} ->
        {:error, {error, description}}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, {"oauth2_error", to_string(reason)}}
    end
  end

  # OAuth2.Strategy callbacks

  @impl OAuth2.Strategy
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl OAuth2.Strategy
  def get_token(client, params, headers) do
    client
    |> put_param(:grant_type, "authorization_code")
    |> put_header("Content-Type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
