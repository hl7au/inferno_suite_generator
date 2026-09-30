FROM ruby:3.3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY inferno_suite_generator.gemspec /app/
COPY lib/inferno_suite_generator/version.rb /app/lib/inferno_suite_generator/version.rb

COPY . /app/

RUN bundle install

ENTRYPOINT ["ruby", "-e", "$LOAD_PATH.unshift(File.expand_path('./lib', Dir.pwd)); require 'inferno_suite_generator'; InfernoSuiteGenerator::Generator.generate(ARGV[0])"]

CMD ["--help"]