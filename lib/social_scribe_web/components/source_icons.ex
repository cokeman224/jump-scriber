defmodule SocialScribeWeb.SourceIcons do
  @moduledoc """
  Renders the Sources icons for the Ask Anything input area.
  Icons represent: Jump AI, Google, HubSpot, Salesforce.
  Also renders contact icons (avatar or provider logo fallback).
  """
  use Phoenix.Component

  def contact_icon(assigns) do
    contact = assigns.contact
    avatar_url = contact[:avatar_url]
    provider = (contact[:provider] || "hubspot") |> String.downcase()

    assigns =
      assigns
      |> assign(:avatar_url, avatar_url)
      |> assign(:provider, provider)
      |> assign(:provider_logo, provider_logo_for(provider))

    ~H"""
    <span class="inline-flex items-center align-middle">
      <%= if @avatar_url do %>
        <img
          src={@avatar_url}
          alt=""
          class="w-4 h-4 rounded-full object-cover flex-shrink-0 inline-block align-middle mr-1"
        />
      <% else %>
        <img
          src={@provider_logo}
          alt={@provider}
          title={String.capitalize(@provider)}
          class="w-4 h-4 rounded-full object-cover flex-shrink-0 inline-block align-middle mr-1"
        />
      <% end %>
    </span>
    """
  end

  defp provider_logo_for("hubspot"), do: "/images/sources/hubspot.svg"
  defp provider_logo_for("salesforce"), do: "/images/sources/salesforce.svg"
  defp provider_logo_for(_), do: "/images/sources/jump.svg"

  def source_icon(assigns) do
    {provider, title} = source_to_icon(assigns.source)
    assigns = assign(assigns, :provider, provider) |> assign(:title, title)

    ~H"""
    <img
      src={"/images/sources/#{@provider}.svg"}
      alt={@title}
      title={@title}
      class="w-5 h-5 rounded-full border-2 border-white flex-shrink-0 object-cover"
    />
    """
  end

  defp source_to_icon("Contact from " <> provider) do
    {String.downcase(provider), "Contact from #{provider}"}
  end

  defp source_to_icon("Meeting: " <> rest), do: {"google", "Meeting: " <> rest}
  defp source_to_icon("General knowledge"), do: {"jump", "General knowledge"}
  defp source_to_icon(source), do: {"jump", source}

  def source_icons(assigns) do
    ~H"""
    <div class="flex -space-x-1.5">
      <img
        src="/images/sources/jump.svg"
        alt="Jump AI"
        title="Jump AI"
        class="w-5 h-5 rounded-full border-2 border-white flex-shrink-0 object-cover"
      />
      <img
        src="/images/sources/google.svg"
        alt="Google"
        title="Google"
        class="w-5 h-5 rounded-full border-2 border-white flex-shrink-0 object-cover"
      />
      <img
        src="/images/sources/hubspot.svg"
        alt="HubSpot"
        title="HubSpot"
        class="w-5 h-5 rounded-full border-2 border-white flex-shrink-0 object-cover"
      />
      <img
        src="/images/sources/salesforce.svg"
        alt="Salesforce"
        title="Salesforce"
        class="w-5 h-5 rounded-full border-2 border-white flex-shrink-0 object-cover"
      />
    </div>
    """
  end
end
