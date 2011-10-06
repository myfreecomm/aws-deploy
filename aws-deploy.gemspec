# -*- encoding: utf-8 -*-
require File.expand_path('../lib/aws-deploy/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Myfreecomm"]
  gem.email         = ["rafael.carvalho@myfreecomm.com.br"]
  gem.description   = %q{Deploy MyFinance at Amazon.}
  gem.summary       = %q{Deploy MyFinance at Amazon.}
  gem.homepage      = "https://github.com/myfreecomm/aws-deploy"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "aws-deploy"
  gem.require_paths = ["lib"]
  gem.version       = Aws::Deploy::VERSION

  gem.add_dependency 'aws', '2.5.6'
end
