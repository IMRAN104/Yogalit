class YogalitAdminsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin
  include ApplicationHelper

  def index
  end

  def reported_non_refund_requested_yoga_sessions
    yoga_sessions = YogaSession.where(video_under_review: true, student_requested_refund: false)
    @reported_student_sessions = build_reported_sessions_hash(yoga_sessions, "student")
    @reported_teacher_sessions = build_reported_sessions_hash(yoga_sessions, "teacher")
  end

  def reported_refund_requested_yoga_sessions
    yoga_sessions = YogaSession.where(video_under_review: true, student_requested_refund: true)
    @reported_sessions = build_reported_sessions_hash(yoga_sessions, "student")
  end

  def teacher_no_show
    yoga_session = YogaSession.find(params[:id])
    student = Student.find(yoga_session[:student_id])
    student_email = User.find(student[:user_id]).email
    teacher = Teacher.find(yoga_session[:teacher_id])
    teacher_email = User.find(teacher[:user_id]).email
    teacher_cancel_count = TeacherEmergencyCancel.where(teacher_id: yoga_session[:teacher_id]).count
    transaction_id = Payment.find(yoga_session[:payment_id]).transaction_id
    yoga_session[:student_refund_given] = true
    yoga_session[:video_under_review] = false
    yoga_session[:video_reviewed] = true

    if teacher[:has_been_blacklisted]########
      # Block Teacher
      teacher[:blocked] = true
      if teacher.save! && Payment.refund_successful?(transaction_id) && yoga_session.save!
        UserMailer.teacher_blocked_email(teacher_email).deliver_now
        UserMailer.student_refund_email(student_email).deliver_now
        flash[:notice] = "Teacher has been blocked due to a previous Blacklisting. Refund given."
      else
        flash[:notice] = "Something went wrong, please try again."
      end
    elsif teacher_cancel_count == 3
      # Blacklist Teacher
      teacher.blacklisted = true
      teacher.has_been_blacklisted = true
      date = Date.parse((Time.now.in_time_zone(teacher[:timezone]) + 2592000).to_s)
      teacher.unblacklist_date = date
      if teacher.save! && Payment.refund_successful?(transaction_id) && yoga_session.save!
        UserMailer.teacher_blacklisted_email(teacher_email).deliver_now
        UserMailer.student_refund_email(student_email).deliver_now
        flash[:notice] = "Teacher has been Blacklisted. Refund given."
      else
        flash[:notice] = "Something went wrong please try again."
      end
    else
      # Add emergency cancellation
      teacher_emergency_cancel = TeacherEmergencyCancel.new
      teacher_emergency_cancel[:teacher_id] = teacher[:id]
      if teacher_emergency_cancel.save! && Payment.refund_successful?(transaction_id) && yoga_session.save!
        UserMailer.teacher_emergency_cancel_email(teacher_email).deliver_now
        UserMailer.student_refund_email(student_email).deliver_now
        flash[:notice] = "Teacher Emergency Cancel initiated. Refund given."
      else
        flash[:notice] = "Something went wrong, please try again."
      end
    end########

    return redirect_to request.referrer
  end

  def build_reported_sessions_hash(yoga_sessions, teacher_or_student)
    reported_sessions = {}
    counter = 1
    if yoga_sessions.empty?
      reported_sessions = "no_data"
    else
      yoga_sessions.each do |ys|
        student = Student.find(ys[:student_id])
        student_email = User.find(student[:user_id]).email
        teacher = Teacher.find(ys[:teacher_id])
        teacher_email = User.find(teacher[:user_id]).email
        if teacher_or_student == "student"
          reported_session = StudentReportedYogaSession.where(yoga_session_id: ys[:id]).first
          next if reported_session.nil?
        else
          reported_session = TeacherReportedYogaSession.where(yoga_session_id: ys[:id]).first
          next if reported_session.nil?
        end
        booked_time = TeacherBookedTime.find(ys[:teacher_booked_time_id])
        reported_sessions["reported_session_#{counter}"] = {}
        reported_sessions["reported_session_#{counter}"]["yoga_session_id"] = ys[:id]
        reported_sessions["reported_session_#{counter}"]["teacher_name"] = "#{teacher[:first_name].capitalize} #{teacher[:last_name].capitalize}"
        reported_sessions["reported_session_#{counter}"]["teacher_email"] = teacher_email
        reported_sessions["reported_session_#{counter}"]["student_name"] = "#{student[:first_name].capitalize} #{student[:last_name].capitalize}"
        reported_sessions["reported_session_#{counter}"]["student_email"] = student_email
        reported_sessions["reported_session_#{counter}"]["teacher_time_range"] = "#{sanitize_date_for_time_only(Time.at(booked_time[:time_range].first).in_time_zone(booked_time[:teacher_timezone]))} - #{sanitize_date_for_time_only(Time.at(booked_time[:time_range].last).in_time_zone(booked_time[:teacher_timezone]))}"
        reported_sessions["reported_session_#{counter}"]["teacher_timezone"] = booked_time[:teacher_timezone]
        reported_sessions["reported_session_#{counter}"]["student_timezone"] = booked_time[:student_timezone]
        reported_sessions["reported_session_#{counter}"]["yoga_type"] = YogaType::ENUMS.key(ys[:yoga_type])
        reported_sessions["reported_session_#{counter}"]["duration"] = booked_time[:duration]
        reported_sessions["reported_session_#{counter}"]["reported_session_description"] = reported_session[:description]
        reported_sessions["reported_session_#{counter}"]["opentok_session_id"] = ys[:opentok_session_id]
        counter += 1
      end
    end
    return reported_sessions
  end

  def teacher_interviews
    @user = User.where(email: params[:teacher_email].downcase).first if params[:email_given]
  end

  def verify_teacher
    teacher = Teacher.where(user_id: params[:id]).first
    teacher_email = User.find(teacher[:user_id]).email
    interview = InterviewBookedTime.where(teacher_id: teacher[:id]).first
    teacher[:is_verified] = true
    interview[:completed] = true
    if teacher.save! && interview.save!
      flash[:notice] = "Teacher has been approved!"
      UserMailer.teacher_verification_email(teacher_email).deliver_now
      return redirect_to yogalit_admins_path
    else
      flash[:notice] = "Something went wrong, please try again."
      return redirect_to request.referrer
    end
  end

  def deny_teacher
    user = User.find(params[:id])
    teacher = Teacher.where(user_id: params[:id]).first
    if teacher[:is_verified]
      flash[:notice] = "This Teacher has already been verified."
      return redirect_to request.referrer
    end
    interview = InterviewBookedTime.where(teacher_id: teacher[:id]).first
    interview[:completed] = true
    if teacher.delete && user.delete && interview.save!
      flash[:notice] = "Teacher has been denied!"
      teacher_email = User.find(teacher[:user_id]).email
      UserMailer.teacher_denial_email(teacher_email).deliver_now
      return redirect_to yogalit_admins_path
    else
      flash[:notice] = "Something went wrong, please try again."
      return redirect_to request.referrer
    end
  end

  def block_student
    ys = YogaSession.find(params[:id])
    teacher_email = User.find(teacher[:user_id]).email
    student = Student.find(ys[:student_id])
    user = User.find(student[:user_id])
    user[:blacklisted] = true
    if user.save!
      UserMailer.student_blocked_email(user.email).deliver_now
      UserMailer.teacher_blocked_student_resolution_email(teacher_email).deliver_now
      flash[:notice] = "The Student has been Blacklisted!"
    else
      flash[:notice] = "Something went wrong, please try again."
    end
    return redirect_to request.referrer
  end

  def dismiss_report_without_action
    ys = YogaSession.find(params[:id])
    ys[:video_under_review] = false
    ys[:video_reviewed] = true
    if ys.save!
      flash[:notice] = "The report was dismissed successfully!"
    else
      flash[:notice] = "The report did not dismiss, please try again."
    end
    return redirect_to request.referrer
  end

  def teacher_payouts
    if Payment.teacher_payouts
      return redirect_to request.referrer
    end
  end

end
