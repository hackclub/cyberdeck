# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # OmniAuth strategy for Hackatime (hackatime.hackclub.com).
    #
    # Hackatime runs Doorkeeper, so this is a stock OAuth2 authorization-code
    # flow with PKCE. Two calls follow the token exchange:
    #
    #   GET /api/v1/authenticated/me        -> id, emails, slack_id,
    #                                          github_username, trust_factor
    #   GET /api/v1/authenticated/api_keys  -> the UUID the editor extension
    #                                          sends with heartbeats
    #
    # The api_keys call needs no particular scope beyond a valid token, but it
    # returns a credential, so it is fetched once here and handed straight to
    # the caller rather than being re-fetched on later requests.
    #
    # Docs: https://hackatime.hackclub.com/docs/oauth/oauth-apps
    class Hackatime < OmniAuth::Strategies::OAuth2
      SITE = "https://hackatime.hackclub.com"

      option :name, "hackatime"
      option :pkce, true
      option :client_options, {
        site: SITE,
        authorize_url: "/oauth/authorize",
        token_url: "/oauth/token"
      }
      # `profile` is granted by default and carries identity.
      # `read` is what the stats endpoints require at review time.
      option :scope, "profile read"

      uid { raw_info["id"].to_s }

      info do
        {
          # Hackatime returns every linked address. The first is not
          # documented as primary, so keep the whole list.
          emails: Array(raw_info["emails"]),
          email: Array(raw_info["emails"]).first,
          nickname: raw_info["github_username"],
          slack_id: raw_info["slack_id"],
          github_username: raw_info["github_username"]
        }
      end

      extra do
        {
          raw_info: raw_info,
          trust_level: raw_info.dig("trust_factor", "trust_level"),
          api_key: api_key
        }
      end

      # Hackatime drops brand-new accounts into its editor-setup wizard before
      # showing the consent screen. This program configures the editor plugin
      # itself inside a Codespace, so those steps are noise.
      #
      # Hackatime reads `skip_setup_flow` back off the continue URL it stashes
      # during sign-in, which is this authorize URL, and opens the wizard on
      # its final screen instead. Undocumented, but it is the escape hatch its
      # own hardware-program path uses. `button_text` labels the button that
      # returns here.
      def authorize_params
        super.tap do |params|
          params[:skip_setup_flow] = 1
          params[:button_text] = "Continue to cyberdeck"
        end
      end

      def raw_info
        @raw_info ||= access_token.get("/api/v1/authenticated/me").parsed
      end

      # Returns the user's Hackatime API key, creating one server-side if the
      # account has none. Never log this value.
      def api_key
        @api_key ||= access_token.get("/api/v1/authenticated/api_keys").parsed["token"]
      rescue ::OAuth2::Error => e
        # A convicted ("red") or pending-deletion user is refused here with a
        # 401. Surface nothing rather than failing the whole callback: the
        # trust check in the controller is what should reject them, with a
        # message that explains why.
        Rails.logger.warn("hackatime api_keys refused: #{e.response&.status}")
        nil
      end

      # Doorkeeper returns the token in a JSON body; omniauth-oauth2 defaults
      # to sending the client credentials in the body too, which Doorkeeper
      # accepts.
      def callback_url
        options[:redirect_uri] || (full_host + callback_path)
      end
    end
  end
end

OmniAuth.config.add_camelization("hackatime", "Hackatime")
