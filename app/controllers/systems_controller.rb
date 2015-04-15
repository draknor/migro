class SystemsController < ApplicationController
  before_action :set_system, only: [:show, :edit, :update, :destroy, :test]

  include SystemsHelper

  # GET /systems
  def index
    @systems = System.all
  end

  # GET /systems/1
  def show
  end

  # GET /systems/new
  def new
    @system = System.new
  end

  # GET /systems/1/edit
  def edit
  end

  # GET /systems/1/test
  def test
    puts "[debug] SystemsController#test: System.system_type = #{@system}.#{@system.system_type}"
    puts "[debug] SystemsController#test: Entities = #{@system.entities}"
    # @system.entities  # Rails seems to be caching this obj in the view across calls
    @params = params

    # enforce 'page' valid value
    page = @params[:page].to_i
    @params[:page] = page < 1 ? 1 : page

    @results = nil
    unless @params[:query].blank?
      @results = @system.search(@params[:entity],@params[:query])
      @results_header = "Search Results #{page_record_range(@results.count,@params[:page],@system.max_per_page)} for '[#{@params[:entity]}] #{@params[:query]}'"
    end

    unless @params[:recent].blank?
      time = @params[:recent].to_time(:utc)
      @results = @system.retrieve(@params[:entity],time,@params[:page])
      @results_header = "Updates for #{page_record_range(@results.count,@params[:page],@system.max_per_page)} #{params[:entity]} records since #{time}"
    end

    if @params[:all] = 'true'
      @results = @system.retrieve(@params[:entity],nil,@params[:page])
      @results_header = "Listing #{page_record_range(@results.count,@params[:page],@system.max_per_page)} #{params[:entity]} records"
    end
  end

  # POST /systems
  def create
    @system = System.new(system_params)

    if @system.save
      redirect_to @system, notice: 'System was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /systems/1
  def update
    if @system.update(system_params)
      redirect_to @system, notice: 'System was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /systems/1
  def destroy
    @system.destroy
    redirect_to systems_url, notice: 'System was successfully destroyed.'
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_system
      @system = System.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def system_params
      params[:system].permit(:name, :ref_url, :integration_type)
    end
end
