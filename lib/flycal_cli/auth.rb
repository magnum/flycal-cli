# frozen_string_literal: true

require "webrick"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"

module FlycalCli
  class Auth
    SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
    REDIRECT_PORT = 9292
    REDIRECT_URI = "http://127.0.0.1:#{REDIRECT_PORT}/oauth2callback"

    class << self
      def credentials
        return nil unless Config.credentials_exist?

        token_store = Google::Auth::Stores::FileTokenStore.new(file: Config.tokens_path)
        client_id = Google::Auth::ClientId.from_file(Config.credentials_path)
        authorizer = Google::Auth::UserAuthorizer.new(
          client_id,
          SCOPE,
          token_store,
          "/oauth2callback"
        )

        creds = authorizer.get_credentials("flycal_user")
        return creds if creds

        nil
      end

      def logged_in?
        creds = credentials
        return false unless creds

        creds.fetch_access_token!
        true
      rescue Signet::AuthorizationError
        false
      end

      def login
        unless Config.credentials_exist?
          raise FlycalCli::Error,
                "Credentials file not found. Create #{Config.credentials_path} with OAuth credentials from Google Cloud Console.\n" \
                "Go to: https://console.cloud.google.com/apis/credentials\n" \
                "Create 'Desktop app' credentials and download the JSON as credentials.json"
        end

        token_store = Google::Auth::Stores::FileTokenStore.new(file: Config.tokens_path)
        client_id = Google::Auth::ClientId.from_file(Config.credentials_path)
        authorizer = Google::Auth::UserAuthorizer.new(
          client_id,
          SCOPE,
          token_store,
          "/oauth2callback"
        )

        creds = authorizer.get_credentials("flycal_user")
        if creds
          creds.fetch_access_token!
          return creds
        end

        # Start local server to receive the auth code
        code = start_redirect_server(authorizer)
        raise FlycalCli::Error, "Authentication cancelled or failed" if code.nil? || code.empty?

        authorizer.get_and_store_credentials_from_code(
          user_id: "flycal_user",
          code: code,
          base_url: "http://127.0.0.1:#{REDIRECT_PORT}"
        )
      end

      def logout
        return true unless File.exist?(Config.tokens_path)

        token_store = Google::Auth::Stores::FileTokenStore.new(file: Config.tokens_path)
        token_store.delete("flycal_user")
        File.delete(Config.tokens_path) if File.exist?(Config.tokens_path)
        true
      end

      private

      def start_redirect_server(authorizer)
        auth_code = nil
        state = SecureRandom.hex(16)
        code_verifier = Google::Auth::UserAuthorizer.generate_code_verifier
        authorizer.code_verifier = code_verifier

        server = WEBrick::HTTPServer.new(
          Port: REDIRECT_PORT,
          BindAddress: "127.0.0.1",
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::FATAL),
          AccessLog: []
        )

        server.mount_proc("/oauth2callback") do |req, res|
          query = req.request_uri.query
          params = query ? URI.decode_www_form(query).to_h : {}

          if params["error"]
            res.status = 400
            res.body = "<h1>Error</h1><p>#{params['error']}: #{params['error_description']}</p>"
            auth_code = nil
          elsif params["code"]
            auth_code = params["code"]
            res.status = 200
            res.body = "<h1>Authentication complete!</h1><p>You can close this window and return to the terminal.</p>"
          end

          Thread.new { server.shutdown }
        end

        url = authorizer.get_authorization_url(
          base_url: REDIRECT_URI.sub("/oauth2callback", ""),
          state: state
        )

        puts "\nOpen this link in your browser to authenticate:\n\n"
        puts "  #{url}\n\n"
        puts "After authentication, you will be redirected back here automatically.\n\n"

        server.start
        auth_code
      end
    end
  end
end
