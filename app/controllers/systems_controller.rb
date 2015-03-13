class SystemsController < ApplicationController
  before_action :set_system, only: [:show, :edit, :update, :destroy, :test]

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

  def test

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
