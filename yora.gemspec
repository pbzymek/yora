Gem::Specification.new do |s|
  s.name        = 'yora'
  s.version     = '0.0.1'
  s.date        = '2020-08-21'
  s.summary     = "A simple Raft distributed consensus implementation"
  s.description = s.summary
  s.authors     = ["Le Huy", "Piotr Bzymek"]
  s.files       = ["lib/yora.rb"]
  s.homepage    = 'http://github.com/pbzymek/yora'
  s.license     = 'MIT'

  s.add_development_dependency 'rubocop'
end
