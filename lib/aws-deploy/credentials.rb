module AwsDeploy
  class Credentials
    REG = /^AWSAccessKeyId=(.*)\r\nAWSSecretKey=(.*)\r\n$/
    def initialize
      file_path = (File.join(File.expand_path("~"), ".aws-credential-file"))
      if ENV["AWS_CREDENTIAL_FILE"]
        file_path = ENV["AWS_CREDENTIAL_FILE"]
      end
      @credentials = File.read(file_path)
    end

    def key
      @credentials =~ REG
      $1
    end
    def token
      @credentials =~ REG
      $2
    end
  end
end