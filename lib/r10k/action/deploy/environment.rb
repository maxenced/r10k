require 'r10k/util/setopts'
require 'r10k/deployment'
require 'r10k/logging'
require 'r10k/action/visitor'

module R10K
  module Action
    module Deploy
      class Environment

        include R10K::Util::Setopts
        include R10K::Logging

        def initialize(opts, argv)
          @opts = opts
          @argv = argv.map { |arg| arg.gsub(/\W/,'_') }
          setopts(opts, {
            :config     => :self,
            :puppetfile => :self,
            :purge      => :self,
            :trace      => :self,
            :forks      => :self
          })

          @purge = true
        end

        def call
          @visit_ok = true
          deployment = R10K::Deployment.load_config(@config)
          deployment.accept(self, @opts[:forks].to_i)
          @visit_ok
        end

        include R10K::Action::Visitor

        private

        def visit_deployment(deployment)
          # Ensure that everything can be preloaded. If we cannot preload all
          # sources then we can't fully enumerate all environments which
          # could be dangerous. If this fails then an exception will be raised
          # and execution will be halted.
          deployment.preload!
          deployment.validate!

          yield

          deployment.purge! if @purge

        ensure
          if (postcmd = deployment.config.setting(:postrun))
            subproc = R10K::Util::Subprocess.new(postcmd)
            subproc.logger = logger
            subproc.execute
          end
        end

        def visit_source(source)
          yield
        end

        def visit_environment(environment)
          if !(@argv.empty? || @argv.any? { |name| environment.dirname == name })
            logger.debug1("Environment #{environment.dirname} does not match environment name filter, skipping")
            return
          end
          status = environment.status
          logger.info "Deploying environment #{environment.path}"
          environment.sync

          if status == :absent || @puppetfile
            if status == :absent
              logger.debug("Environment #{environment.dirname} is new, updating all modules")
            end
            yield
          end
        end

        def visit_puppetfile(puppetfile)
          puppetfile.load
          yield
          puppetfile.purge!
        end

        def visit_module(mod)
          logger.info "Deploying module #{mod.path}"
          mod.sync
        end
      end
    end
  end
end
