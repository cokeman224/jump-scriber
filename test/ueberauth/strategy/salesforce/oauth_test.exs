defmodule Ueberauth.Strategy.Salesforce.OAuthTest do
  use ExUnit.Case, async: false

  alias Ueberauth.Strategy.Salesforce.OAuth

  @moduletag :ueberauth_salesforce

  setup do
    orig_config = Application.get_env(:ueberauth, OAuth, [])
    orig_env = System.get_env("SALESFORCE_BASE_URL")
    on_exit(fn ->
      Application.put_env(:ueberauth, OAuth, orig_config)
      if orig_env, do: System.put_env("SALESFORCE_BASE_URL", orig_env), else: System.delete_env("SALESFORCE_BASE_URL")
    end)
    :ok
  end

  describe "client/1" do
    test "uses sandbox URLs when site is test.salesforce.com" do
      Application.put_env(:ueberauth, OAuth, site: "https://test.salesforce.com", client_id: "id", client_secret: "secret")
      client = OAuth.client()
      assert client.site == "https://test.salesforce.com"
      assert client.authorize_url =~ "test.salesforce.com"
      assert client.token_url =~ "test.salesforce.com"
    end

    test "uses production URLs when site is login.salesforce.com" do
      Application.put_env(:ueberauth, OAuth, site: "https://login.salesforce.com", client_id: "id", client_secret: "secret")
      client = OAuth.client()
      assert client.site == "https://login.salesforce.com"
      assert client.authorize_url =~ "login.salesforce.com"
      assert client.token_url =~ "login.salesforce.com"
    end

    test "uses sandbox when SALESFORCE_BASE_URL is test.salesforce.com" do
      Application.put_env(:ueberauth, OAuth, [])
      System.put_env("SALESFORCE_BASE_URL", "https://test.salesforce.com")
      client = OAuth.client()
      assert client.site == "https://test.salesforce.com"
      assert client.authorize_url =~ "test.salesforce.com"
    end
  end
end
