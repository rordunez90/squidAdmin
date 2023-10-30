<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Domain extends Model
{
    use HasFactory;
    /**
     * The attributes that are mass assignable.
     *
     * @var array
     */
    protected $fillable = [
        'name', 'is_interest', 'percent_interest'
    ];

    /**
     * Get the logs for the user.
     */
    public function logs(): HasMany
    {
        return $this->hasMany(Loginfo::class);
    }
}
