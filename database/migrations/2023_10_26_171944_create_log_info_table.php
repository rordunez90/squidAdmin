<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('loginfo', function (Blueprint $table) {
            $table->id();
            $table->dateTime('date');
            $table->string('ip');
            $table->string('status_code');
            $table->integer('size');
            $table->string('operation');
            $table->string('url');
            $table->string('content_tipe');
            $table->integer('internal_size');
            $table->timestamps();
            $table->foreignId('user_id');
            $table->foreignId('domain_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('loginfo');
    }
};
