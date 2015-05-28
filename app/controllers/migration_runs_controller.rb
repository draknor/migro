class MigrationRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :set_migration_run, only: [:show, :edit, :update, :destroy, :execute, :abort]

  # GET /migration_runs
  def index
    @migration_runs = MigrationRun.all
  end

  # GET /migration_runs/1
  def show
  end

  # GET /migration_runs/new
  def new
    @migration_run = MigrationRun.new
  end

  # POST /migration_runs
  def create
    @migration_run = MigrationRun.new(migration_run_params)
    @migration_run.user = @user

    if @migration_run.save
      redirect_to @migration_run, notice: 'Migration run was successfully created.'
    else
      render :new
    end
  end

  # GET /migration_runs/1/execute
  def execute
    unless @migration_run.created?
      flash[:error] = 'Cannot execute run - wrong status'
      redirect_to migration_runs_path
    else
      migration = MigrationService.new(@migration_run)
      migration.error_check
      if migration.error.count > 0
        flash[:error] = 'Execution preparation errors: ' + migration.error.join(', ')
      elsif MigrationJob.perform_later(@migration_run.id)
        flash[:notice] = 'Execution has been queued'
        @migration_run.queued!
      else
        flash[:error] = 'Unknown error occurred'
      end
      redirect_to migration_run_path(@migration_run)
    end

  end

  def abort
    unless @migration_run.running?
      flash[:error] = 'Cannot abort run - no longer running'
      redirect_to migration_runs_path
    else
      @migration_run.abort
      flash[:notice] = 'Execution is aborting!'
    end
    redirect_to migration_run_path(@migration_run)

  end

  # Probably scrap the rest of these methods - leave stubs here for now ####################

  # # GET /migration_runs/1/edit
  def edit
  end


  # # PATCH/PUT /migration_runs/1
  def update
    if @migration_run.update(migration_run_params)
      redirect_to @migration_run, notice: 'Migration run was successfully updated.'
    else
      render :edit
    end
  end
  #
  # # DELETE /migration_runs/1
  def destroy
  #   @migration_run.destroy
  #   redirect_to migration_runs_url, notice: 'Migration run was successfully destroyed.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_migration_run
      @migration_run = MigrationRun.find(params[:id])
    end

    def set_user
      @user = current_user
    end

    # Only allow a trusted parameter "white list" through.
    def migration_run_params
      params.require(:migration_run).permit(:name, :source_system_id, :destination_system_id, :user_id, :entity_type, :all_records, :record_list, :phase, :start_page)
    end
end
