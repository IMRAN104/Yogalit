class CreateFavoriteTeachers < ActiveRecord::Migration[5.1]
  def change
    create_table :favorite_teachers do |t|
      t.belongs_to :student, index: true
      t.belongs_to :teacher, index: true
      t.timestamps null: false
    end
  end
end
