require 'spec_helper'

# This spec was generated by rspec-rails when you ran the scaffold generator.
# It demonstrates how one might use RSpec to specify the controller code that
# was generated by Rails when you ran the scaffold generator.
#
# It assumes that the implementation code is generated by the rails scaffold
# generator.  If you are using any extension libraries to generate different
# controller code, this generated spec may or may not pass.
#
# It only uses APIs available in rails and/or rspec-rails.  There are a number
# of tools you can use to make these specs even more expressive, but we're
# sticking to rails and rspec-rails APIs to keep things simple and stable.
#
# Compared to earlier versions of this generator, there is very limited use of
# stubs and message expectations in this spec.  Stubs are only used when there
# is no simpler way to get a handle on the object needed for the example.
# Message expectations are only used when there is no simpler way to specify
# that an instance is receiving a specific message.

describe PublicStatusesController do

  # This should return the minimal set of attributes required to create a valid
  # PublicStatus. As you add validations to PublicStatus, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) { { "id" => "1" } }

  # This should return the minimal set of values that should be in the session
  # in order to pass any filters (e.g. authentication) defined in
  # PublicStatusesController. Be sure to keep this updated too.
  let(:valid_session) { {} }

  describe "GET index" do
    it "assigns all public_statuses as @public_statuses" do
      public_status = PublicStatus.create! valid_attributes
      get :index, {}, valid_session
      assigns(:public_statuses).should eq([public_status])
    end
  end

  describe "GET show" do
    it "assigns the requested public_status as @public_status" do
      public_status = PublicStatus.create! valid_attributes
      get :show, {:id => public_status.to_param}, valid_session
      assigns(:public_status).should eq(public_status)
    end
  end

  describe "GET new" do
    it "assigns a new public_status as @public_status" do
      get :new, {}, valid_session
      assigns(:public_status).should be_a_new(PublicStatus)
    end
  end

  describe "GET edit" do
    it "assigns the requested public_status as @public_status" do
      public_status = PublicStatus.create! valid_attributes
      get :edit, {:id => public_status.to_param}, valid_session
      assigns(:public_status).should eq(public_status)
    end
  end

  describe "POST create" do
    describe "with valid params" do
      it "creates a new PublicStatus" do
        expect {
          post :create, {:public_status => valid_attributes}, valid_session
        }.to change(PublicStatus, :count).by(1)
      end

      it "assigns a newly created public_status as @public_status" do
        post :create, {:public_status => valid_attributes}, valid_session
        assigns(:public_status).should be_a(PublicStatus)
        assigns(:public_status).should be_persisted
      end

      it "redirects to the created public_status" do
        post :create, {:public_status => valid_attributes}, valid_session
        response.should redirect_to(PublicStatus.last)
      end
    end

    describe "with invalid params" do
      it "assigns a newly created but unsaved public_status as @public_status" do
        # Trigger the behavior that occurs when invalid params are submitted
        PublicStatus.any_instance.stub(:save).and_return(false)
        post :create, {:public_status => { "id" => "invalid value" }}, valid_session
        assigns(:public_status).should be_a_new(PublicStatus)
      end

      it "re-renders the 'new' template" do
        # Trigger the behavior that occurs when invalid params are submitted
        PublicStatus.any_instance.stub(:save).and_return(false)
        post :create, {:public_status => { "id" => "invalid value" }}, valid_session
        response.should render_template("new")
      end
    end
  end

  describe "PUT update" do
    describe "with valid params" do
      it "updates the requested public_status" do
        public_status = PublicStatus.create! valid_attributes
        # Assuming there are no other public_statuses in the database, this
        # specifies that the PublicStatus created on the previous line
        # receives the :update_attributes message with whatever params are
        # submitted in the request.
        PublicStatus.any_instance.should_receive(:update_attributes).with({ "id" => "1" })
        put :update, {:id => public_status.to_param, :public_status => { "id" => "1" }}, valid_session
      end

      it "assigns the requested public_status as @public_status" do
        public_status = PublicStatus.create! valid_attributes
        put :update, {:id => public_status.to_param, :public_status => valid_attributes}, valid_session
        assigns(:public_status).should eq(public_status)
      end

      it "redirects to the public_status" do
        public_status = PublicStatus.create! valid_attributes
        put :update, {:id => public_status.to_param, :public_status => valid_attributes}, valid_session
        response.should redirect_to(public_status)
      end
    end

    describe "with invalid params" do
      it "assigns the public_status as @public_status" do
        public_status = PublicStatus.create! valid_attributes
        # Trigger the behavior that occurs when invalid params are submitted
        PublicStatus.any_instance.stub(:save).and_return(false)
        put :update, {:id => public_status.to_param, :public_status => { "id" => "invalid value" }}, valid_session
        assigns(:public_status).should eq(public_status)
      end

      it "re-renders the 'edit' template" do
        public_status = PublicStatus.create! valid_attributes
        # Trigger the behavior that occurs when invalid params are submitted
        PublicStatus.any_instance.stub(:save).and_return(false)
        put :update, {:id => public_status.to_param, :public_status => { "id" => "invalid value" }}, valid_session
        response.should render_template("edit")
      end
    end
  end

  describe "DELETE destroy" do
    it "destroys the requested public_status" do
      public_status = PublicStatus.create! valid_attributes
      expect {
        delete :destroy, {:id => public_status.to_param}, valid_session
      }.to change(PublicStatus, :count).by(-1)
    end

    it "redirects to the public_statuses list" do
      public_status = PublicStatus.create! valid_attributes
      delete :destroy, {:id => public_status.to_param}, valid_session
      response.should redirect_to(public_statuses_url)
    end
  end

end
