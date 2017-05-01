class StudentsController < ApplicationController
  before_action :authenticate_user!
  include ApplicationHelper

  def new
    @student = Student.new
    return redirect_to students_path if Student.student_exists?(current_user)
  end

  def create
    student = Student.new(student_params)
    student[:user_id] = current_user[:id]
    if student.save!
      flash[:notice] = "Your Student information was saved!"
      path = students_path
    else
      flash[:notice] = "Your Student information was not saved."
      path = request.referrer
    end
    return redirect_to path
  end

  def index
    @student = Student.where(user_id: current_user).first
    @upcoming_yoga_sessions = get_upcoming_yoga_sessions
    @favorite_teachers = get_favorite_teachers
  end

  def get_favorite_teachers
    teachers = []
    favorite_teachers = FavoriteTeacher.where(student_id: @student)
    favorite_teachers.each do |ft|
      teachers << Teacher.find(ft[:teacher_id])
    end
    return teachers
  end

  def get_upcoming_yoga_sessions
    upcoming_yoga_sessions = {}
    next_booked_times = TeacherBookedTime.where("session_date >= ?", Date.today).where(student_id: @student).limit(15).order(session_date: :asc)
    if next_booked_times.empty?
      return "no-upcoming-sessions"
    else
      counter = 1
      next_booked_times.each do |bt|
        yoga_session = YogaSession.where(teacher_booked_time_id: bt).first
        teacher = Teacher.find(yoga_session[:teacher_id])
        date = sanitize_date_for_view(bt[:session_date].to_s)
        day_of_week = bt[:session_date].strftime("%A")
        time_range = sanitize_date_range_for_view(bt[:time_range], bt[:student_timezone])
        split_date = bt[:session_date].to_s.split("-")
        Time.zone = bt[:student_timezone]
        split_time_range = time_range.split(" - ")
        start_time = sanitize_date_for_time_only(Time.parse(split_time_range[0]).in_time_zone(bt[:student_timezone]))
        end_time = sanitize_date_for_time_only((Time.parse(split_time_range[1]) - 1).in_time_zone(bt[:student_timezone]))
        timestamp_time = Time.parse(split_time_range[0]).in_time_zone(bt[:teacher_timezone])
        timestamp = Time.zone.local(split_date[0], split_date[1], split_date[2], timestamp_time.strftime("%k"), timestamp_time.strftime("%M"))
        upcoming_yoga_sessions["yoga_session_#{counter}"] = {}
        upcoming_yoga_sessions["yoga_session_#{counter}"]["yoga_session_id"] = yoga_session[:id]
        upcoming_yoga_sessions["yoga_session_#{counter}"]["first_name"] = teacher[:first_name]
        upcoming_yoga_sessions["yoga_session_#{counter}"]["last_name"] = teacher[:last_name]
        upcoming_yoga_sessions["yoga_session_#{counter}"]["date"] = date
        upcoming_yoga_sessions["yoga_session_#{counter}"]["day_of_week"] = day_of_week
        upcoming_yoga_sessions["yoga_session_#{counter}"]["time_range"] = "#{start_time} - #{end_time}"
        upcoming_yoga_sessions["yoga_session_#{counter}"]["duration"] = bt[:duration]
        upcoming_yoga_sessions["yoga_session_#{counter}"]["timezone"] = bt[:student_timezone]
        upcoming_yoga_sessions["yoga_session_#{counter}"]["timestamp"] = timestamp
        counter += 1
      end
      return sorted = upcoming_yoga_sessions.sort_by{|k, v| v["timestamp"]}
    end
  end

  def edit
    @student = Student.find(params[:id])
  end

  def update
    student = Student.find(params[:id])
    student[:first_name] = params[:student][:first_name].downcase
    student[:last_name] = params[:student][:last_name].downcase
    student[:phone] = params[:student][:phone]
    if student.save!
      flash[:notice] = "Your profile info was update successfully!"
      path = students_path
    else
      flash[:notice] = "Your profile info was not updated."
      path = request.referrer
    end
    return redirect_to path
  end

  private

  def student_params
    params.require(:student).permit(:user_id, :first_name, :last_name, :phone)
  end
end
