{{-- Blade sample for highlighting tests --}}
@extends('layouts.app')

@section('title', 'Dashboard')

@php
    $count = count($users);
    $label = $count === 1 ? 'user' : 'users';
@endphp

@section('content')
    <div class="container" id="main" x-data="{ open: false }">
        <h1>{{ $title }} &amp; {{ __('messages.welcome', ['name' => $user->name]) }}</h1>
        <p>{!! $rawHtml !!}</p>

        @if ($count > 0)
            <ul>
                @foreach ($users as $user)
                    <li wire:click="select({{ $user->id }})" @class(['active' => $loop->first])>
                        {{ $loop->iteration }}: {{ $user->name }}
                    </li>
                @endforeach
            </ul>
        @elseif ($count === 0)
            <p>No {{ $label }} yet.</p>
        @else
            @include('partials.error', ['code' => 500])
        @endif

        @forelse ($posts as $post)
            <x-post-card :post="$post" class="mb-4" />
        @empty
            <x-alert type="info">Nothing to show.</x-alert>
        @endforelse

        @auth
            <a href="{{ route('logout') }}" @click="open = !open">Log out</a>
        @endauth

        @switch($role)
            @case('admin')
                <span>Admin</span>
                @break
            @default
                <span>Member</span>
        @endswitch

        <form method="POST" action="{{ route('users.store') }}">
            @csrf
            @method('PUT')
            <input type="text" name="name" value="{{ old('name') }}">
            @error('name')
                <span class="error">{{ $message }}</span>
            @enderror
        </form>
    </div>
@endsection

@push('scripts')
    <script>
        const total = {{ $count }};
        console.log(`Loaded ${total} users`);
    </script>
    <style>
        .container { max-width: 960px; }
    </style>
@endpush

@verbatim
    <div>{{ notBlade }}</div>
@endverbatim

<?php echo strtoupper($label); ?>
