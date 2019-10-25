module Scenarios
  ##
  # Add code owners to PR
  class CheckCodeOwners
    def run
      jira = JIRA::Client.new SimpleConfig.jira.to_h
      # noinspection RubyArgCount
      abort('Only IOS project supports this feature') if SimpleConfig.jira.issue.include?('ADR')
      issue = jira.Issue.find(SimpleConfig.jira.issue)
      LOGGER.info "Try to get all PR in status OPEN from #{issue.key}"
      pullrequests = issue.pullrequests(SimpleConfig.git.to_h)
                       .filter_by_status('OPEN')
                       .filter_by_source_url(SimpleConfig.jira.issue)

      if pullrequests.empty?
        issue.post_comment <<-BODY
      {panel:title=CodeOwners checker!|borderStyle=dashed|borderColor=#ccc|titleBGColor=#b8b8e8|bgColor=#d2d2d2}
        В тикете нет открытых PR! Проверять нечего {noformat}¯\\_(ツ)_/¯{noformat}
      {panel}
        BODY
      end

      LOGGER.info "Found #{pullrequests.prs.size} PR in status OPEN"

      pullrequests.each do |pr|
        LOGGER.info "Start work with PR: #{pr.pr['url']}"
        pr_repo   = pr.repo
        pr_name   = pr.pr['name']
        pr_id     = pr.pr['id']
        reviewers = pr.pr['reviewers']
        pr_author = pr.pr['author']
        # Prepare account_id reviewers list from PR
        old_reviewers = get_reviewers_id(reviewers, pr_repo)
        # Get author id for case when he will be one of owners
        author_id     = get_reviewers_id(pr_author, pr_repo).first
        diff_stats    = {}
        owners_config = {}
        # Get PR diff and owners_config
        with pr_repo do
          LOGGER.info 'Try to diff stats from BB'
          diff_stats = get_pullrequests_diffstats(pr_id)
          LOGGER.info 'Success!'
          LOGGER.info "Try to get owners.yml file for project #{remote.url.repo}"
          owners_config_path = "#{File.expand_path('../../../', __FILE__)}/bin/#{remote.url.repo}/owners.yml"
          owners_config      = YAML.load_file owners_config_path
          LOGGER.info "Success!Got file from #{owners_config_path}"
        end

        modified_files = get_modified_links(diff_stats)
        # Get codeOwners
        new_reviewers = get_owners(owners_config, modified_files)
        # Prepare new_reviewers_list
        new_reviewers_list = prepare_new_reviewers_list(old_reviewers, new_reviewers, author_id)

        # Add info and new reviewers in PR
        with pr_repo do
          LOGGER.info 'Try to add reviewers to PR'
          add_info_in_pullrequest(pr_id, 'Description without reviewers ok', new_reviewers_list, pr_name)
          LOGGER.info 'Success! Everything fine!'
        end
      end
    end

    def with(instance, &block)
      instance.instance_eval(&block)
      instance
    end

    def get_modified_links(diff_stats)
      LOGGER.info 'Try to get modified files'
      result   = []
      statuses = %w[modified removed]
      diff_stats[:values].each do |diff|
        result << diff[:old][:path] if statuses.include? diff[:status]
      end
      LOGGER.info 'Success!'
      result
    end

    def get_reviewers_id(reviewers, pr_repo)
      LOGGER.info 'Try to get current reviewers id'
      result    = []
      reviewers = [reviewers] unless reviewers.is_a? Array
      with pr_repo do
        reviewers.each do |user|
          # Name with space should replace with +
          result << get_reviewer_info(user['name'].sub(' ', '+')).first[:mention_id]
        end
      end
      LOGGER.info "Success! Result: #{result}"
      result
    end

    def get_owners(owners_config, diff)
      LOGGER.info 'Try to get owners ids'
      result = {}
      diff.each do |item|
        owners_config.each do |product|
          result[product[0]] = product[1]['owners'] if product[1]['files'].include? item
        end
      end
      LOGGER.info "Success! Result: #{result}"
      result
    end

    def prepare_new_reviewers_list(old_reviewers, owners, author_id)
      LOGGER.info 'Try to prepare reviewers list for add to PR'
      result = []
      old_reviewers.each { |reviewer| result << { account_id: reviewer } }
      owners.each do |owner|
        owner[1].each do |id|
          result << { account_id: id } unless id == author_id
        end
      end
      LOGGER.info "Success! Result: #{result}"
      result
    end
  end
end
