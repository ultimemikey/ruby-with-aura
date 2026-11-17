require "openssl"

module Aura

  module Auth

    class Unauthorized < StandardError; end

    SESSION_KEY = :aura_user

    ITERATIONS  = 200_000
    DIGEST      = "SHA256"
    KEY_LENGTH  = 32
    SALT_LENGTH = 16

    module_function

    def sign_in(session, user)
      session[SESSION_KEY] = user
      user
    end

    def sign_out(session)
      session.delete(SESSION_KEY)
      nil
    end

    def current_user(session)
      session[SESSION_KEY]
    end

    def authenticated?(session)
      !current_user(session).nil?
    end

    def authorized?(user, role)
      roles_for(user).include?(role.to_s)
    end

    def authorize!(user, role)
      return true if authorized?(user, role)

      raise Unauthorized, "user is not authorized for role: #{role}"
    end

    def hash_password(password)
      salt   = ::OpenSSL::Random.random_bytes(SALT_LENGTH)
      digest = pbkdf2(password, salt)

      "pbkdf2_#{DIGEST.downcase}$#{ITERATIONS}$#{b64(salt)}$#{b64(digest)}"
    end

    def verify_password(password, hash)
      algorithm, iterations, salt_b64, digest_b64 = hash.to_s.split("$")
      return false unless algorithm&.start_with?("pbkdf2")

      salt     = unb64(salt_b64)
      expected = unb64(digest_b64)
      return false if salt.nil? || expected.nil?

      actual = pbkdf2(password, salt, digest: digest_for(algorithm), iterations: iterations.to_i)
      secure_compare(expected, actual)
    end

    def pbkdf2(password, salt, digest: DIGEST, iterations: ITERATIONS)
      ::OpenSSL::PKCS5.pbkdf2_hmac(
        password.to_s, salt, iterations, KEY_LENGTH, ::OpenSSL::Digest.new(digest)
      )
    end

    def roles_for(user)
      candidate =
        if user.is_a?(::Hash)
          user[:roles] || user["roles"] || user[:role] || user["role"]
        elsif user.respond_to?(:roles)
          user.roles
        elsif user.respond_to?(:role)
          user.role
        end

      Array(candidate).map(&:to_s)
    end

    def digest_for(algorithm)
      algorithm.to_s.sub(/\Apbkdf2_/, "").upcase
    end

    def b64(bytes)
      [bytes].pack("m0")
    end

    def unb64(value)
      return nil if value.nil?

      value.unpack1("m0")
    rescue ArgumentError
      nil
    end

    def secure_compare(expected, actual)
      return false unless expected.bytesize == actual.bytesize

      ::OpenSSL.fixed_length_secure_compare(expected, actual)
    rescue NoMethodError

      expected.bytes.zip(actual.bytes).reduce(0) { |acc, (a, b)| acc | (a ^ b) }.zero?
    end
  end
end
