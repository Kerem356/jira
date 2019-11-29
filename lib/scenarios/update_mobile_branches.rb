module Scenarios
  ##
  # Try to merge develop branch in ticket's branches
  class UpdateMobileBranches
    def find_by_filter(issue, filter)
      issue.jql("filter=#{filter}", max_results: 100)
    rescue JIRA::HTTPError => jira_error
      error_message = jira_error.response['body_exists'] ? jira_error.message : jira_error.response.body
      LOGGER.error "Error in JIRA with the search by filter #{filter}: #{error_message}"
      []
    end

    def with(instance, &block)
      instance.instance_eval(&block)
      instance
    end

    def update_issue(issue)
      pullrequests = issue.pullrequests(SimpleConfig.git.to_h).filter_by_status('OPEN')
      LOGGER.info "Found #{pullrequests.prs.count} pullrequests".green
      pullrequests.each do |pr| # rubocop:disable Metrics/BlockLength
        next unless pr.pr['destination']['branch'].include? 'develop'
        begin
          pr_repo = git_repo(pr.pr['destination']['url'])
          # Prepare repo
          pr_repo.pull('origin', 'develop')
          branch_name = pr.pr['source']['branch']
          LOGGER.info "Try to update PR: #{branch_name}".green
          with pr_repo do
            checkout branch_name
            pull('origin', branch_name)
            pull('origin', 'develop')
            push(pr_repo.remote('origin'), branch_name)
          end
          LOGGER.info "Successful update:  #{branch_name}"
        rescue StandardError => e
          if e.message.include?('Merge conflict')
            LOGGER.error "Update PR failed. Reason: Merge Conflict. LOG: #{e.message}"
            issue.post_comment <<-BODY
              {panel:title=Build status error|borderStyle=dashed|borderColor=#ccc|titleBGColor=#F7D6C1|bgColor=#FFFFCE}
                  Не удалось подмержить develop в PR: #{pr.pr['url']}
                  *Причина:* Merge conflict
                  LOG: #{e.message}
              {panel}
            BODY
          else
            LOGGER.error "Update PR failed. Reason: #{e.message}"
            issue.post_comment <<-BODY
              {panel:title=Build status error|borderStyle=dashed|borderColor=#ccc|titleBGColor=#F7D6C1|bgColor=#FFFFCE}
                  *Не удалось подмержить develop в PR*: #{pr.pr['url']}
                  *Причина:* #{e.message}
              {panel}
            BODY
          end
          issue.transition 'Reopen'
          next
        end
      end
    end

    def run
      adr_filter = 30_361
      # Get all tickets
      jira = JIRA::Client.new SimpleConfig.jira.to_h
      # noinspection RubyArgCount
      issue = jira.Issue.find(SimpleConfig.jira.issue)
      LOGGER.info("Start work after #{issue.key} was merged")
      project_name = issue.fields['project']['key']

      abort('IOS ticket was merged, so i will skip this task. Only ADR project supports this feature') if project_name.include?('IOS')

      LOGGER.info "Try to find all tasks from filter #{adr_filter}".green
      issues = find_by_filter(jira.Issue, adr_filter)
      LOGGER.info "Found #{issues.count} issues".green
      count_max = issues.count
      counter   = 1

      issues.each do |i|
        LOGGER.info "Work with #{i.key} (#{counter}/#{count_max})"
        update_issue(i)
        counter += 1
      end
    end
  end
end
