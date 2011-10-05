module AwsDeploy
  class Credentials
    REG = /^AWSAccessKeyId=(.*)\r\nAWSSecretKey=(.*)\r\n$/
    def initialize
      @credentials = File.read(File.join(File.expand_path("~"), ".aws-credential-file"))
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