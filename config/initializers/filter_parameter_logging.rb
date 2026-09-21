# frozen_string_literal: true

# Anything on this list is replaced with [FILTERED] in the logs.
#
# This app handles three OAuth tokens, a Hackatime API key, and three client
# secrets. None of them may ever reach a log line, a stack trace, or an error
# reporter. Add to this list before adding a field that holds a credential,
# not after.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn
  code
  access_token refresh_token id_token
  api_key apikey
  encrypted_value
  client_secret
  state code_verifier code_challenge
]
