COMPOSE = "docker compose".freeze
APP     = "interview-dev".freeze

namespace :docker do
  desc "Build the Docker image"
  task :build do
    sh "#{COMPOSE} build"
  end

  desc "Build the Docker image from scratch (no cache)"
  task :rebuild do
    sh "#{COMPOSE} build --no-cache"
  end

  desc "Start all containers in the background"
  task :start do
    sh "#{COMPOSE} up -d"
  end

  desc "Stop all containers"
  task :stop do
    sh "#{COMPOSE} down"
  end

  desc "Restart all containers"
  task restart: %i[stop start]

  desc "Tail live logs for the Rails app"
  task :logs do
    sh "#{COMPOSE} logs -f #{APP}"
  end

  desc "Open a Rails console inside the container"
  task :console do
    sh "#{COMPOSE} exec #{APP} ./bin/rails console"
  end

  desc "Open a shell inside the app container"
  task :shell do
    sh "#{COMPOSE} exec #{APP} sh"
  end

  desc "Run the full test suite inside the container"
  task :test do
    sh "#{COMPOSE} exec #{APP} ./bin/rails test"
  end
end
